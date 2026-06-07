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

`enable` is idempotent — it wires the hook globally once and is safe to call at boot.

## Architecture

All source lives under `lib/robot_lab/audit/`.

**`Audit`** (`audit.rb`) — Entry point module. `Audit.enable(db_path:)` creates the `EventLog` and registers the `Hook` via `RobotLab.on`. Requires `robot_lab` to be loaded first.

**`EventLog`** (`audit/event_log.rb`) — SQLite wrapper. Creates two tables on first open:
- `network_runs` — one row per `Network#run` call: `run_id`, `network_name`, `input`, `result`, `error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms`
- `audit_events` — one row per robot run or tool call: same fields plus `event_type` (`"robot_run"` or `"tool_call"`), `robot_name`, `tool_name`

Public query methods: `network_runs(limit:)`, `events_for(run_id)`, `recent_errors(limit:)`.

**`Hook`** (`audit/hook.rb`) — Subclass of `RobotLab::Hook` with `namespace = :audit`. Uses `Thread.current` keyed locals to track `run_id` and `started_at` across the before/after pairs:
- `before_network_run` / `after_network_run` — writes the `network_runs` row
- `before_run` / `after_run` — writes a `"robot_run"` audit event
- `before_tool_call` / `after_tool_call` — writes a `"tool_call"` audit event

All timestamps are UTC ISO 8601 with millisecond precision.

## Key Constraints

- `robot_lab` must be loaded before `robot_lab/audit` — the Hook subclass requires `RobotLab::Hook` to exist.
- `EventLog` is not thread-safe by itself; SQLite handles concurrent writes via its own locking.
- `safe_json` on the hook silently falls back to `inspect` for non-serializable values — do not rely on JSON structure for complex tool arguments.
- Run IDs are UUIDs stored in `Thread.current` — not propagated across Fibers or Ractors.

## Testing

- Minitest with SimpleCov (branch coverage tracked, no minimum threshold enforced yet)
- Tests use `Tmpdir` for isolated SQLite databases — never write to a shared file in tests
- Coverage baseline: ~47% line / ~3% branch — test suite is thin relative to implementation
