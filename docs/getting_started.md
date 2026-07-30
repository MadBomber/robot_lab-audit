# Getting Started

## Prerequisites

- Ruby 3.2+ (per the gemspec's `required_ruby_version`)
- `robot_lab` — `robot_lab/audit` requires `RobotLab::Hook` to already be defined, so `robot_lab` must be `require`d first.
- SQLite — the gem depends on the `sqlite3` gem directly; no separate database server to run.

## Installation

Add to your `Gemfile`:

```ruby
gem "robot_lab"
gem "robot_lab-audit"
```

Then:

```sh
bundle install
```

Or install directly:

```sh
gem install robot_lab-audit
```

## Enabling Globally

```ruby
require "robot_lab"
require "robot_lab/audit"

RobotLab::Audit.enable(db_path: "~/.robot_lab/audit.db")

network = RobotLab.create_network(...)
network.run(message: "do something")
```

`RobotLab::Audit.enable(db_path:)`:

1. Instantiates `RobotLab::Audit::EventLog`, which opens (or creates) the SQLite
   file at `db_path`, creating any missing parent directories along the way.
2. Assigns the log to `RobotLab::Audit::Hook.event_log`.
3. Registers the hook globally via `RobotLab.on(Hook)`.

Calling `enable` again with a new `db_path` simply repoints the hook at a new
`EventLog` — it is safe to call once at boot.

If `robot_lab` has not been loaded yet, `enable` raises
`RobotLab::Audit::Error` ("robot_lab must be loaded before calling
RobotLab::Audit.enable").

## What Gets Logged

| Table | One row per | Key columns |
|-------|--------------|-------------|
| `network_runs` | `Network#run` call | `run_id`, `network_name`, `input`, `result`, `error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms` |
| `audit_events` | `Robot#run` or `Tool#call` | `run_id`, `event_type`, `robot_name`, `tool_name`, `input`, `output`, `error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms` |

`event_type` is `"robot_run"` or `"tool_call"`. All `input`/`output`/`result`
values are stored as JSON text. Timestamps are UTC, ISO 8601, with millisecond
precision.

Every event produced while a `Network#run` is in flight shares that run's
`run_id`, so you can pull the entire trace for one execution with
`events_for(run_id)` (see [Querying the Log](querying.md)).

Standalone `Robot#run` calls made outside of a network are recorded too —
their `run_id` column is `nil`.

## Minimal Example

```ruby
require "robot_lab"
require "robot_lab/audit"
require "tmpdir"

RobotLab::Audit.enable(db_path: File.join(Dir.mktmpdir, "audit.db"))

robot = RobotLab.build(name: "greeter", system_prompt: "You are a friendly greeter.")
robot.run("Say hello")

log = RobotLab::Audit::Hook.event_log
log.events_for(nil).each do |event|
  puts "#{event[:event_type]}  #{event[:robot_name]}  #{event[:duration_ms]}ms"
end
```

The gem ships a fuller, self-contained demo with no API keys required — it
uses deterministic stubbed robots and tools so the audit trail is
reproducible:

```sh
bundle exec ruby examples/01_basic_usage.rb
```

It walks through five scenarios: enabling the hook, a two-robot network run,
tool call capture, error capture, and scoping the hook to a single robot.

## Scoping to a Robot or Network

`RobotLab::Audit.enable` registers the hook globally — every robot and
network in the process gets logged. To audit only specific objects, skip
`enable` and register the hook directly instead:

```ruby
RobotLab::Audit::Hook.event_log = RobotLab::Audit::EventLog.new(db_path: "audit.db")

robot.on(RobotLab::Audit::Hook)
# or
network.on(RobotLab::Audit::Hook)
```

Robots and networks that never call `.on(RobotLab::Audit::Hook)` produce no
audit entries at all — the hook simply never fires for them.

If you had previously called `RobotLab::Audit.enable`, clear the global hook
registry first (`RobotLab.hooks.clear`) so the same events aren't logged
twice — once globally and once for the specific object.

## Key Constraints

- `robot_lab` must be `require`d before `robot_lab/audit` — see Prerequisites above.
- `EventLog` is not thread-safe by itself; SQLite handles concurrent writes via its own file locking.
- Run IDs are correlated via `Thread.current` — they are **not** propagated across Fibers or Ractors. Work dispatched off-thread (e.g. via `robot_lab-ractor`) will not share a `run_id` with its parent network run.
- `safe_json` (used internally to serialise `input`/`output`) silently falls back to `#inspect` for values that can't be JSON-encoded — don't assume every `input`/`output` column is valid JSON when a tool passes an unusual argument type.
