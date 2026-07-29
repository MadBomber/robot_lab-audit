# How It Works

## Schema

`EventLog#initialize` opens the SQLite file at `db_path` (expanding `~` and
creating any missing parent directories via `FileUtils.mkdir_p`), then runs a
`CREATE TABLE IF NOT EXISTS` schema batch — safe to call every time the
process boots.

```sql
CREATE TABLE network_runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id        TEXT    NOT NULL UNIQUE,
  network_name  TEXT,
  input         TEXT,
  result        TEXT,
  error_class   TEXT,
  error_message TEXT,
  started_at    TEXT    NOT NULL,
  finished_at   TEXT,
  duration_ms   REAL
);

CREATE TABLE audit_events (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id        TEXT,
  event_type    TEXT NOT NULL,
  robot_name    TEXT,
  tool_name     TEXT,
  input         TEXT,
  output        TEXT,
  error_class   TEXT,
  error_message TEXT,
  started_at    TEXT NOT NULL,
  finished_at   TEXT,
  duration_ms   REAL
);
```

Two tables, no foreign key constraint between them — `audit_events.run_id`
is simply a shared correlation string, nullable for events that happen
outside of any network run.

| Column | Present on | Notes |
|--------|-----------|-------|
| `run_id` | both | `NOT NULL UNIQUE` on `network_runs` (one row per run); nullable, non-unique on `audit_events` (many rows share a run) |
| `event_type` | `audit_events` only | `"robot_run"` or `"tool_call"` |
| `robot_name` / `tool_name` | `audit_events` only | `tool_name` is `nil` for `"robot_run"` events |
| `network_name` | `network_runs` only | taken from `ctx.network&.name` |
| `input` / `output` / `result` | both | JSON-encoded text (see [JSON Serialisation](#json-serialisation-safe_json) below) |
| `error_class` / `error_message` | both | populated from the exception object when the call raised, else `nil` |
| `started_at` / `finished_at` | both | UTC, ISO 8601, millisecond precision (`Time#iso8601(3)`) |
| `duration_ms` | both | `(finished - started) * 1000`, rounded to 2 decimal places |

## Hook Callback Mapping

`RobotLab::Audit::Hook` is a subclass of `RobotLab::Hook` with
`self.namespace = :audit`. It implements three before/after callback pairs
from RobotLab's [Hook system](https://github.com/MadBomber/robot_lab/blob/main/docs/guides/hooks.md):

| Hook family | Callbacks | Writes |
|-------------|-----------|--------|
| `:network_run` | `before_network_run`, `after_network_run` | one `network_runs` row |
| `:run` | `before_run`, `after_run` | one `audit_events` row, `event_type: "robot_run"` |
| `:tool_call` | `before_tool_call`, `after_tool_call` | one `audit_events` row, `event_type: "tool_call"` |

`before_network_run`, `after_network_run`, `after_run`, and `after_tool_call`
all `return unless event_log` (or `event_log && current_run_id`) as their
first line — they are true no-ops when `Hook.event_log` is `nil`. This is what
makes it safe to `require "robot_lab/audit"` without calling `enable`, and
what makes per-robot/per-network scoping work cleanly.

`before_run` and `before_tool_call` are a partial exception: they run
unconditionally, stashing `Time.now.utc` on `ctx.local.started_at` even when
`event_log` is `nil`. That write has no observable effect on its own — it's
local, namespace-scoped state (see below) that only gets read if the matching
`after_*` callback goes on to record a row, and that callback still checks
`event_log` before touching the database. So the *net* behavior is the same
(nothing is written when auditing is off), it's just the `after_*` half of
each pair that carries the guard, not the `before_*` half.

### Network run lifecycle

```
before_network_run(ctx)
  → generates a new run_id  (SecureRandom.uuid)
  → stores run_id and started_at in Thread.current

  ... network executes: robots run, tools are called ...

after_network_run(ctx)
  → writes the network_runs row using the thread-local run_id/started_at
  → clears both thread-locals in an `ensure` block
```

`after_network_run` is a no-op if there is no `current_run_id` — this
guards against `after_network_run` firing without a matching
`before_network_run` (for example, if the hook was registered mid-flight).

### Robot run and tool call lifecycle

`before_run` / `before_tool_call` don't touch `Thread.current` at all —
they stash `started_at` on `ctx.local`, which is namespace-scoped state that
RobotLab's `HookContext` provides per-callback-pair (see
`ctx.with_namespace(:audit)` in the test suite for how this is activated).

`after_run` / `after_tool_call` then read `ctx.local.started_at`, look up the
thread-local `run_id` set by an enclosing `before_network_run` (or `nil` if
there is none), and write one `audit_events` row via the shared private
`record_audit_event` helper.

### Run ID correlation

All events produced while a given `Network#run` is executing — the network
run itself, every robot invocation, every tool call — share the same
`run_id`, because that ID lives in `Thread.current` for the duration of the
network run and every robot/tool callback reads it. This is what makes
`EventLog#events_for(run_id)` a full execution trace rather than a fragment.

Standalone `Robot#run` or `Tool#call` invocations made outside of any
network run see `current_run_id` as `nil` — they still get logged, just
without a correlating run.

## Thread-Local State

Two `Thread.current` keys carry state between the `before_*` and `after_*`
halves of the network-run lifecycle:

| Key | Set in | Cleared in | Purpose |
|-----|--------|-----------|---------|
| `:robot_lab_audit_run_id` | `before_network_run` | `after_network_run` (`ensure`) | correlates all events within one network run |
| `:robot_lab_audit_network_started_at` | `before_network_run` | `after_network_run` (`ensure`) | computes the network run's `duration_ms` |

Because this is `Thread.current` rather than `ctx.local`, run correlation
does **not** cross Fiber or Ractor boundaries — parallel work dispatched via
`robot_lab-ractor`, for instance, will not inherit the parent network run's
`run_id`. `before_run`/`before_tool_call` state, by contrast, uses `ctx.local`
and is scoped per-callback-pair regardless of thread.

## JSON Serialisation (`safe_json`)

`input`/`output` values (tool arguments, robot request/response payloads) are
serialised with a private `safe_json` helper:

```ruby
def safe_json(value)
  return nil if value.nil?

  JSON.generate(value)
rescue JSON::GeneratorError, TypeError
  value.inspect
end
```

If a value can't be JSON-encoded (circular references, unsupported types),
the column falls back to Ruby's `#inspect` string instead of raising. Don't
assume every `input`/`output` value is parseable JSON — check for `nil`
first if you write tooling against the column, and be prepared for an
`inspect`-style string on the rare unencodable payload.

`network_runs.input` and `.result` use dedicated extractors
(`extract_network_input`, `extract_network_result`) that look for a
`:message`/`'message'` key on the network context, or — for the result — a
`.reply` on `result.value` when the result object responds to `:value` (the
shape `simple_flow`'s result wrapper returns), falling back to `safe_json`
and finally to `#inspect` if anything raises.

## Error Capture

When a network run, robot run, or tool call raises, the hook's
`error_fields` helper extracts `error_class` (the exception's class name as
a string) and `error_message` (the exception's message) from whatever
`ctx.error` / `ctx.tool_error` object RobotLab's Hook system populates. Both
columns are `nil` on success. `EventLog#recent_errors` filters
`audit_events` down to rows where `error_class IS NOT NULL`.

## RobotLab Extension Registration

`lib/robot_lab/audit.rb` ends with:

```ruby
require_relative 'audit/hook' if defined?(RobotLab::Hook)

if defined?(RobotLab) && RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:audit, RobotLab::Audit)
end
```

The `Hook` subclass is only loaded when `RobotLab::Hook` is already defined,
and extension registration only runs when `RobotLab.register_extension`
exists — both guards make `require "robot_lab/audit"` safe even in contexts
where `robot_lab` hasn't been (fully) loaded, though calling `enable` in that
state still raises (see [Getting Started](getting_started.md)).
