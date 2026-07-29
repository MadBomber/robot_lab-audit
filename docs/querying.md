# Querying the Log

`RobotLab::Audit::EventLog` is the only public query surface. Get a handle
to the active log via the hook (when using global `enable`):

```ruby
log = RobotLab::Audit::Hook.event_log
```

or hold onto the `EventLog` instance yourself if you constructed it directly
for scoped auditing (see [Getting Started — Scoping](getting_started.md#scoping-to-a-robot-or-network)).

Each query method returns an `Array` of `Hash` objects keyed by column name
as symbols (e.g. `row[:run_id]`, `row[:duration_ms]`).

## `network_runs(limit: 100)`

Recent network runs, newest first (ordered by `started_at DESC`).

```ruby
log.network_runs(limit: 20).each do |run|
  status = run[:error_class] ? "FAILED (#{run[:error_class]})" : "OK"
  puts "#{run[:run_id]}  #{run[:network_name]}  #{status}  #{run[:duration_ms]}ms"
end
```

Columns returned: `id`, `run_id`, `network_name`, `input`, `result`,
`error_class`, `error_message`, `started_at`, `finished_at`, `duration_ms`.

## `events_for(run_id)`

Every `audit_events` row for one network run, ordered chronologically
(`ORDER BY started_at`) — the full execution trace for that run: every robot
invocation and every tool call, interleaved in the order they actually
happened.

```ruby
run_id = log.network_runs.first[:run_id]

log.events_for(run_id).each do |event|
  label = event[:tool_name] || event[:robot_name]
  puts "#{event[:event_type].ljust(10)} #{label.ljust(20)} #{event[:duration_ms]}ms"
end
```

Columns returned: `id`, `run_id`, `event_type`, `robot_name`, `tool_name`,
`input`, `output`, `error_class`, `error_message`, `started_at`,
`finished_at`, `duration_ms`.

Standalone `Robot#run`/`Tool#call` invocations made outside any network run
are recorded with `run_id: nil` — pass `nil` to `events_for` to retrieve
them:

```ruby
log.events_for(nil)
```

## `recent_errors(limit: 50)`

`audit_events` rows where `error_class IS NOT NULL`, newest first — every
failed robot run or tool call across all network runs (and standalone
calls), regardless of `run_id`.

```ruby
log.recent_errors.each do |event|
  puts "#{event[:started_at]}  #{event[:robot_name]}/#{event[:tool_name]}  " \
       "#{event[:error_class]}: #{event[:error_message]}"
end
```

This is the fastest way to answer "what broke recently?" without knowing a
specific `run_id` up front.

## Querying with Raw SQL

`EventLog` doesn't try to be a full reporting layer — for anything beyond
the three methods above, query the SQLite file directly. It's a plain
single-file database; any SQL client works.

```bash
sqlite3 ~/.robot_lab/audit.db \
  "SELECT event_type, robot_name, tool_name, duration_ms, error_class
   FROM audit_events
   WHERE run_id = 'some-run-id'
   ORDER BY started_at;"
```

Useful ad hoc queries:

```sql
-- Slowest tool calls across all runs
SELECT tool_name, robot_name, duration_ms, started_at
FROM audit_events
WHERE event_type = 'tool_call'
ORDER BY duration_ms DESC
LIMIT 20;

-- Error rate by robot
SELECT robot_name,
       COUNT(*) AS total,
       SUM(CASE WHEN error_class IS NOT NULL THEN 1 ELSE 0 END) AS errors
FROM audit_events
WHERE event_type = 'robot_run'
GROUP BY robot_name;

-- Network runs that failed
SELECT run_id, network_name, error_class, error_message, started_at
FROM network_runs
WHERE error_class IS NOT NULL
ORDER BY started_at DESC;
```

Because `input`/`output`/`result` are stored as JSON text, SQLite's
[JSON1 functions](https://www.sqlite.org/json1.html) (`json_extract`, etc.)
can reach into them directly:

```sql
SELECT json_extract(input, '$.text') AS text_arg, duration_ms
FROM audit_events
WHERE tool_name = 'word_count_tool';
```

Remember that a small fraction of `input`/`output` values may be a
`#inspect` fallback string rather than valid JSON (see
[How It Works — JSON Serialisation](how_it_works.md#json-serialisation-safe_json)) — `json_extract` will
simply return `NULL` for those rows rather than raising.
