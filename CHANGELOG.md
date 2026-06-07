# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `.loki` Asgard task file: `test`, `rubocop`, `rubocop_fix`, `flog`, `flay`, `quality`, `build`, `install`, `release`, and `console` tasks via the Asgard task runner
- `flay_check` Rake task: structural code duplication gate (mass threshold 50); integrated into the `quality` Rake task
- `flay`, `flog`, `rubocop`, and `racc` gems added to development dependencies (`rubocop` was previously absent; `racc` required explicitly for Ruby 4.0 which dropped it from default gems)
- `test_output.txt`, `flay_output.txt`, `flog_output.txt`, and `rubocop_output.txt` added to `.gitignore`

### Changed
- `test/test_helper.rb`: test output redirected to `test_output.txt` via `$stdout` reassignment; `TerminalSummaryReporter` prints a single PASS/FAIL summary line to the terminal
- `Rakefile`: `rubocop` and `rubocop_fix` tasks removed (now owned by Asgard); `flay_check` integrated into the `quality` gate

## [0.1.0] - 2026-05-28

### Added

- `RobotLab::Audit::EventLog` — SQLite-backed append-only log with two tables:
  `network_runs` (one row per `Network#run`) and `audit_events` (one row per robot
  invocation or tool call). Query helpers: `network_runs`, `events_for(run_id)`,
  `recent_errors`.
- `RobotLab::Audit::Hook` — `RobotLab::Hook` subclass that captures lifecycle events
  via `before/after_network_run`, `before/after_run`, and `before/after_tool_call`.
  Uses thread-local storage to correlate all events within a single network run under
  one `run_id`. Records wall-clock timestamps and duration in milliseconds for each
  event.
- `RobotLab::Audit.enable(db_path:)` — one-call setup that creates the `EventLog`,
  assigns it to the hook, and registers the hook globally with `RobotLab.on`.

[Unreleased]: https://github.com/MadBomber/robot_lab-audit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MadBomber/robot_lab-audit/releases/tag/v0.1.0
