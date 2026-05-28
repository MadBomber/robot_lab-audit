#!/usr/bin/env ruby
# frozen_string_literal: true

# robot_lab-audit Demo
#
# Shows how robot_lab-audit plugs into RobotLab via the Hook system.
# Five scenarios are demonstrated:
#
#   1. Enable   — one call wires up global audit logging
#   2. Network  — a two-robot network run and its audit trail
#   3. Tools    — tool calls captured with args, results, and timing
#   4. Errors   — tool errors recorded with error_class and error_message
#   5. Scoped   — attach the hook to one robot instead of globally
#
# No API keys required. Robots and tools use deterministic stubs so the
# demo is fully reproducible and the focus stays on the audit log.
#
# Usage:
#   bundle exec ruby examples/audit_demo.rb

require_relative "common"
require "tmpdir"
require "json"

# ── Fake LLM response ───────────────────────────────────────────────────────────

FakeResponse = Data.define(:content, :tool_calls, :stop_reason) do
  def initialize(content:, tool_calls: nil, stop_reason: "end_turn") = super
  def reply = content
end

# ── Tools ────────────────────────────────────────────────────────────────────────

class WordCountTool < RobotLab::Tool
  description "Counts words in a text string"
  param :text, type: "string", desc: "The text to analyse"

  def execute(text:)
    { word_count: text.split.size, status: "ok" }
  end
end

class SentimentTool < RobotLab::Tool
  description "Returns a sentiment score for a text string"
  param :text, type: "string", desc: "The text to score"

  def execute(text:)
    score = text.downcase.include?("great") ? 0.9 : 0.5
    { score: score, label: score > 0.7 ? "positive" : "neutral" }
  end
end

class FailingTool < RobotLab::Tool
  description "Always raises a ToolError (for error logging demo)"
  param :reason, type: "string", desc: "Failure reason"

  def execute(reason:)
    raise RobotLab::ToolError, "Simulated failure: #{reason}"
  end
end

# ── Build deterministic stub robots ─────────────────────────────────────────────

def stub_robot(name:, system_prompt:, response:, tools: [])
  robot = RobotLab.build(name: name, system_prompt: system_prompt, local_tools: tools)
  robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
    FakeResponse.new(content: response)
  end
  robot
end

# ── Display helpers ──────────────────────────────────────────────────────────────

def print_network_runs(runs)
  if runs.empty?
    puts "  (none)"
    return
  end
  runs.each do |run|
    status = run[:error_class] ? "#{ExOut::RED}FAILED#{ExOut::RESET}" : "#{ExOut::GREEN}OK#{ExOut::RESET}"
    puts "  #{ExOut::BOLD}run_id#{ExOut::RESET}  #{ExOut::GRAY}#{run[:run_id]}#{ExOut::RESET}"
    kv "network",     run[:network_name]
    kv "status",      status
    kv "started_at",  run[:started_at]
    kv "duration_ms", "#{run[:duration_ms]}ms"
    kv "input",       run[:input]
    kv "result",      run[:result]&.then { |r| r.length > 60 ? "#{r[0..57]}..." : r }
    puts
  end
end

def print_events(events, label: nil)
  if events.empty?
    puts "  (none)"
    return
  end
  puts "  #{label}\n\n" if label
  events.each_with_index do |ev, i|
    type_color = ev[:event_type] == "tool_call" ? ExOut::CYAN : ExOut::GREEN
    error_flag = ev[:error_class] ? " #{ExOut::RED}[#{ev[:error_class]}]#{ExOut::RESET}" : ""
    puts "  #{i + 1}. #{type_color}#{ev[:event_type]}#{ExOut::RESET}#{error_flag}"
    kv "robot",       ev[:robot_name]
    kv "tool",        ev[:tool_name] || "—"
    kv "duration_ms", "#{ev[:duration_ms]}ms"
    kv "input",       ev[:input]&.then { |v| v.length > 58 ? "#{v[0..55]}..." : v }
    kv "output",      ev[:output]&.then { |v| v.length > 58 ? "#{v[0..55]}..." : v }
    kv "error",       ev[:error_message] if ev[:error_class]
    puts
  end
end

# ════════════════════════════════════════════════════════════════════════════════
# Demo
# ════════════════════════════════════════════════════════════════════════════════

DB_DIR  = Dir.mktmpdir("robot_lab_audit_demo_")
DB_PATH = File.join(DB_DIR, "audit.db")

banner "robot_lab-audit Demo"

# ── 1. Enable ────────────────────────────────────────────────────────────────────

section "1. Enabling the Audit Hook"

puts <<~TEXT
  One call creates the SQLite database, assigns it to the hook, and
  registers the hook globally with RobotLab.on(Hook).

TEXT

puts "  #{ExOut::BOLD}RobotLab::Audit.enable(db_path: \"~/.robot_lab/audit.db\")#{ExOut::RESET}"
RobotLab::Audit.enable(db_path: DB_PATH)
log = RobotLab::Audit::Hook.event_log
kv "DB path", DB_PATH, color: ExOut::GRAY

# ── 2. Network run ───────────────────────────────────────────────────────────────

section "2. Network Run"

puts <<~TEXT
  A two-robot content pipeline: an analyst followed by a summariser.
  The audit hook captures the network run and each robot invocation
  automatically — no changes to robot or network setup required.

TEXT

analyst = stub_robot(
  name:          "analyst",
  system_prompt: "You analyse text and produce a structured report.",
  response:      "Analysis complete. Positive sentiment. 11 words."
)

summariser = stub_robot(
  name:          "summariser",
  system_prompt: "You distil analyst output into one sentence.",
  response:      "Great writing — positive tone and concise."
)

network = RobotLab.create_network(name: "content_pipeline") do
  task :analyse,   analyst,    depends_on: :none
  task :summarise, summariser, depends_on: :analyse
end

input = "This is a great piece of writing that deserves careful review."
kv "Input", "\"#{input}\""
puts

network.run(message: input)

puts "  Network run complete.\n\n"

runs = log.network_runs
print_network_runs(runs)

run_id = runs.first&.dig(:run_id)
if run_id
  puts "  Events for run #{ExOut::GRAY}#{run_id}#{ExOut::RESET}:\n\n"
  print_events(log.events_for(run_id))
end

# ── 3. Tool calls ────────────────────────────────────────────────────────────────

section "3. Tool Calls"

puts <<~TEXT
  Tool invocations are captured in audit_events with event_type "tool_call".
  Each row records the tool name, arguments, result, robot, and timing.
  Tool calls outside a network run have a nil run_id.

TEXT

word_count = WordCountTool.new
word_count.instance_variable_set(:@robot, analyst)

sentiment = SentimentTool.new
sentiment.instance_variable_set(:@robot, analyst)

word_count.call({ "text" => input })
sentiment.call({ "text" => input })

all_tool_events = log.instance_variable_get(:@db)
                     .execute("SELECT * FROM audit_events WHERE event_type = 'tool_call'")
                     .map do |r|
                       keys = %i[id run_id event_type robot_name tool_name input output
                                 error_class error_message started_at finished_at duration_ms]
                       keys.zip(r).to_h
                     end

print_events(all_tool_events)

# ── 4. Error capture ─────────────────────────────────────────────────────────────

section "4. Error Capture"

puts <<~TEXT
  When a tool raises RobotLab::ToolError, the error is caught, a graceful
  string is returned to the LLM, and the audit log records error_class and
  error_message for post-mortem analysis.

TEXT

failing = FailingTool.new
failing.instance_variable_set(:@robot, analyst)
failing.call({ "reason" => "network timeout" })

print_events(log.recent_errors, label: "recent_errors (newest first):")

# ── 5. Scoped audit ───────────────────────────────────────────────────────────────

section "5. Scoped Audit (Per-Robot)"

puts <<~TEXT
  Instead of global registration, attach the hook to specific robots only.
  Clear the global registry first, point Hook.event_log at a fresh database,
  then call robot.on(Hook) on the robots you want to audit. Robots without
  the hook produce no audit entries.

TEXT

scoped_db_path = File.join(DB_DIR, "scoped.db")
scoped_log     = RobotLab::Audit::EventLog.new(db_path: scoped_db_path)

RobotLab.hooks.clear
RobotLab::Audit::Hook.event_log = scoped_log

audited_robot = stub_robot(
  name:          "audited_robot",
  system_prompt: "This robot is explicitly audited.",
  response:      "Audited robot response."
)
audited_robot.on(RobotLab::Audit::Hook)

silent_robot = stub_robot(
  name:          "silent_robot",
  system_prompt: "This robot has no audit hook.",
  response:      "Silent robot response — not in any audit log."
)

audited_robot.run("run with auditing")
silent_robot.run("run without auditing")

scoped_events = scoped_log.instance_variable_get(:@db)
                           .execute("SELECT * FROM audit_events")
                           .map do |r|
                             keys = %i[id run_id event_type robot_name tool_name input output
                                       error_class error_message started_at finished_at duration_ms]
                             keys.zip(r).to_h
                           end

kv "Scoped DB", scoped_db_path, color: ExOut::GRAY
kv "Audited",   "audited_robot  (hook registered)"
kv "Silent",    "silent_robot   (no hook — absent from log)"
puts
print_events(scoped_events)

# ── Summary ───────────────────────────────────────────────────────────────────────

hr
puts
puts "#{ExOut::BOLD}Audit log summary#{ExOut::RESET}"

total_events = log.instance_variable_get(:@db)
                  .execute("SELECT COUNT(*) FROM audit_events").first.first

kv "Global DB",     DB_PATH
kv "Network runs",  log.network_runs.size.to_s
kv "Total events",  total_events.to_s
kv "Error events",  log.recent_errors.size.to_s
kv "Scoped DB",     scoped_db_path
kv "Scoped events", scoped_events.size.to_s
puts
