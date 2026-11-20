# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Gem Does

`robot_lab-audit` is a SQLite-backed execution audit log for RobotLab. It hooks into the `RobotLab::Hook` system to record every network run, robot invocation, and tool call with timestamps and duration — enabling post-mortem analysis without changing application code.

## Commands

```bash
bundle exec rake test        # Run full test suite
ruby -Ilib:test test/<file>  # Run a single test file

bin/console                  # IRB session with gem loaded
```

## Enabling

```ruby
require 'robot_lab'
require 'robot_lab/audit'

RobotLab::Audit.enable(db_path: "~/.robot_lab/audit.db")
# All subsequent network and robot runs are recorded automatically
```

`enable` is idempotent — it wires the hook globally once (`Audit.registered?`) and is safe to call at boot; a repeat call only repoints the hook at a new `EventLog`.

## Architecture

The entry point is `lib/robot_lab/audit.rb`; the rest of the source lives under `lib/robot_lab/audit/`.

**`Audit`** (`audit.rb`) — Entry point module. `Audit.enable(db_path:)` creates the `EventLog` and registers the `Hook` via `RobotLab.on`. Requires `robot_lab` to be loaded first.

**`EventLog`** (`audit/event_log.rb`) — SQLite wrapper. Creates two tables on first open:
- `network_runs` — one row per `Network#run` call: `run_id`, `network_name`, `input`, `result`, `error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms`
- `audit_events` — one row per robot run or tool call: `run_id`, `event_type` (`"robot_run"` or `"tool_call"`), `robot_name`, `tool_name`, `input`, `output`, `error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms`

Public query methods: `network_runs(limit:)`, `events_for(run_id)`, `recent_errors(limit:)`.

**`Hook`** (`audit/hook.rb`) — Subclass of `RobotLab::Hook` with `namespace = :audit`. Uses fiber storage (`Fiber[]`) to track `run_id` and the network's `started_at` across the network-run before/after pair; robot-run and tool-call pairs keep `started_at` on `ctx.local`:
- `before_network_run` / `after_network_run` — writes the `network_runs` row
- `before_run` / `after_run` — writes a `"robot_run"` audit event
- `before_tool_call` / `after_tool_call` — writes a `"tool_call"` audit event
- `on_error` — core calls this instead of `after_*` when a robot or network run raises; writes the same row with `error_class`/`error_message` set (task contexts are ignored)

All timestamps are UTC ISO 8601 with millisecond precision.

## Key Constraints

- `robot_lab` must be loaded before `robot_lab/audit` — the Hook subclass requires `RobotLab::Hook` to exist.
- `EventLog` is not thread-safe by itself; SQLite handles concurrent writes via its own locking.
- `safe_json` on the hook silently falls back to `inspect` when `JSON.generate` raises a `JSON::JSONError` or `TypeError` (e.g. `NaN`/`Infinity` floats, circular references); arbitrary objects are stored as a JSON string of their `to_s` — do not rely on JSON structure for complex tool arguments.
- Run IDs are UUIDs stored in fiber storage (`Fiber[]`) — inherited by Fibers and Threads created during the network run (so concurrent tasks keep the `run_id`), but not propagated into Ractors.

## Testing

- Minitest with SimpleCov (branch coverage tracked, no minimum threshold enforced yet)
- Tests use `Dir.mktmpdir` for isolated SQLite databases — never write to a shared file in tests
- Coverage baseline: ~97% line / ~66% branch
