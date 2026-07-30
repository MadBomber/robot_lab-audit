# robot_lab-audit

A SQLite-backed execution audit log for the [RobotLab](https://github.com/MadBomber/robot_lab) LLM agent framework.

`RobotLab::Audit` plugs into RobotLab's [Hook system](https://github.com/MadBomber/robot_lab/blob/main/docs/guides/hooks.md) and writes one row per network run, robot invocation, and tool call to a local SQLite database — timestamps, JSON input/output, errors, and duration in milliseconds. Zero changes required to your robots, networks, or tools.

```ruby
require "robot_lab"
require "robot_lab/audit"

RobotLab::Audit.enable(db_path: "~/.robot_lab/audit.db")

# All subsequent network and robot runs are recorded automatically.
network = RobotLab.create_network(...)
network.run(message: "do something")
```

Every event from a single `Network#run` shares the same `run_id`, so the full
execution trace — which robots ran, which tools they called, what each one
returned, and how long it took — can be reconstructed after the fact for
post-mortem analysis or debugging.

## Navigation

- [Getting Started](getting_started.md) — installation, enabling the hook, a minimal example, scoping to one robot or network
- [How It Works](how_it_works.md) — the SQLite schema, how each Hook callback maps to a row, run_id correlation, thread-local state, JSON serialisation
- [Querying the Log](querying.md) — the `EventLog` query API and raw SQL examples for post-mortem analysis

## At a Glance

| | |
|---|---|
| **Storage** | SQLite (via the `sqlite3` gem) — one file, no server |
| **Tables** | `network_runs`, `audit_events` |
| **Wiring** | `RobotLab::Hook` subclass (`RobotLab::Audit::Hook`), namespace `:audit` |
| **Enable globally** | `RobotLab::Audit.enable(db_path:)` |
| **Enable per robot/network** | `robot.on(RobotLab::Audit::Hook)` / `network.on(RobotLab::Audit::Hook)` |
| **Query API** | `EventLog#network_runs`, `#events_for(run_id)`, `#recent_errors` |

## Links

- [RobotLab Core](https://github.com/MadBomber/robot_lab)
- [RubyGems](https://rubygems.org/gems/robot_lab-audit)
- [GitHub](https://github.com/MadBomber/robot_lab-audit)
