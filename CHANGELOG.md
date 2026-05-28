# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
