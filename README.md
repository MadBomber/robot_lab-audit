# robot_lab-audit

A [RobotLab](https://github.com/MadBomber/robot_lab) extension gem that writes a
structured execution audit log to SQLite. Every network run, robot invocation, and
tool call is recorded as a row — timestamps, inputs, outputs, errors, and duration —
so you can query what happened after the fact.

Plugs into RobotLab's `Hook` system. Zero changes to your robots or networks; opt in
by calling `RobotLab::Audit.enable`.

## Installation

Add to your Gemfile:

```ruby
gem "robot_lab-audit"
```

Or install directly:

```bash
gem install robot_lab-audit
```

## Usage

```ruby
require "robot_lab"
require "robot_lab/audit"

RobotLab::Audit.enable(db_path: "~/.robot_lab/audit.db")

# All network runs and robot runs from here on are logged automatically.
network = RobotLab.create_network(...)
network.run(message: "do something")
```

The database file and any missing parent directories are created automatically.

### What gets logged

| Table | One row per | Key columns |
|-------|-------------|-------------|
| `network_runs` | `Network#run` call | `run_id`, `network_name`, `input`, `result`, `error_*`, `started_at`, `finished_at`, `duration_ms` |
| `audit_events` | `Robot#run` or `Tool#call` | `run_id`, `event_type`, `robot_name`, `tool_name`, `input`, `output`, `error_*`, `started_at`, `finished_at`, `duration_ms` |

`event_type` is `"robot_run"` or `"tool_call"`. All input/output values are JSON.
Timestamps are ISO 8601 with millisecond precision.

All events within a single `Network#run` share the same `run_id`, so you can
reconstruct the full execution trace for any network run.

Standalone `Robot#run` calls (outside a network) are also recorded; their `run_id`
column will be `nil`.

### Querying the log

`EventLog` provides three convenience methods:

```ruby
log = RobotLab::Audit::Hook.event_log

log.network_runs(limit: 100)       # recent network runs, newest first
log.events_for("some-run-id")      # all events for one run, ordered by time
log.recent_errors(limit: 50)       # events where error_class is not null
```

Each method returns an array of hashes keyed by column name.

You can also query the SQLite database directly with any SQL tool:

```bash
sqlite3 ~/.robot_lab/audit.db \
  "SELECT event_type, robot_name, tool_name, duration_ms, error_class
   FROM audit_events
   WHERE run_id = 'some-run-id'
   ORDER BY started_at;"
```

### Scoping to a robot or network

`RobotLab::Audit.enable` registers the hook globally. To limit logging to a specific
robot or network, register the hook directly on that object instead:

```ruby
RobotLab::Audit::Hook.event_log = RobotLab::Audit::EventLog.new(db_path: "audit.db")

robot.on(RobotLab::Audit::Hook)
# or
network.on(RobotLab::Audit::Hook)
```

## Schema

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

## Development

```bash
bundle install
bundle exec rake test       # run tests
bundle exec rake            # default: test
bin/console                 # IRB with gem loaded
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/MadBomber/robot_lab-audit.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
