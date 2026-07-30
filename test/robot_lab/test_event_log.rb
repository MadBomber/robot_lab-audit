# frozen_string_literal: true

require 'test_helper'

class TestEventLog < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log = RobotLab::Audit::EventLog.new(db_path: File.join(@dir, 'audit.db'))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_record_network_run_and_retrieve
    @log.record_network_run(
      run_id: 'run-001',
      network_name: 'pipeline',
      input: '{"message":"hello"}',
      result: '"ok"',
      error_class: nil,
      error_message: nil,
      started_at: '2026-01-01T00:00:00.000Z',
      finished_at: '2026-01-01T00:00:01.000Z',
      duration_ms: 1000.0
    )

    runs = @log.network_runs
    assert_equal 1, runs.size
    run = runs.first
    assert_equal 'run-001',  run[:run_id]
    assert_equal 'pipeline', run[:network_name]
    assert_equal 1000.0,     run[:duration_ms]
  end

  def test_record_robot_run_event
    @log.record_event(
      run_id: 'run-001',
      event_type: 'robot_run',
      robot_name: 'classifier',
      tool_name: nil,
      input: '"classify this"',
      output: '"category_a"',
      error_class: nil,
      error_message: nil,
      started_at: '2026-01-01T00:00:00.000Z',
      finished_at: '2026-01-01T00:00:00.500Z',
      duration_ms: 500.0
    )

    events = @log.events_for('run-001')
    assert_equal 1, events.size
    event = events.first
    assert_equal 'robot_run',  event[:event_type]
    assert_equal 'classifier', event[:robot_name]
    assert_nil event[:tool_name]
  end

  def test_record_tool_call_event
    @log.record_event(
      run_id: 'run-001',
      event_type: 'tool_call',
      robot_name: 'ops_bot',
      tool_name: 'deploy_tool',
      input: '{"env":"staging","version":"1.2.3"}',
      output: '"deployed"',
      error_class: nil,
      error_message: nil,
      started_at: '2026-01-01T00:00:00.100Z',
      finished_at: '2026-01-01T00:00:00.300Z',
      duration_ms: 200.0
    )

    events = @log.events_for('run-001')
    assert_equal 1, events.size
    event = events.first
    assert_equal 'tool_call',   event[:event_type]
    assert_equal 'deploy_tool', event[:tool_name]
    assert_equal '{"env":"staging","version":"1.2.3"}', event[:input]
  end

  def test_recent_errors_returns_only_error_rows
    @log.record_event(
      run_id: 'run-001', event_type: 'robot_run', robot_name: 'bot',
      tool_name: nil, input: nil, output: nil,
      error_class: nil, error_message: nil,
      started_at: '2026-01-01T00:00:00.000Z', finished_at: '2026-01-01T00:00:00.100Z',
      duration_ms: 100.0
    )
    @log.record_event(
      run_id: 'run-001', event_type: 'robot_run', robot_name: 'bot',
      tool_name: nil, input: nil, output: nil,
      error_class: 'RuntimeError', error_message: 'oops',
      started_at: '2026-01-01T00:00:01.000Z', finished_at: '2026-01-01T00:00:01.050Z',
      duration_ms: 50.0
    )

    errors = @log.recent_errors
    assert_equal 1, errors.size
    assert_equal 'RuntimeError', errors.first[:error_class]
  end

  def test_events_for_scopes_by_run_id
    @log.record_event(
      run_id: 'run-001', event_type: 'robot_run', robot_name: 'a',
      tool_name: nil, input: nil, output: nil, error_class: nil, error_message: nil,
      started_at: '2026-01-01T00:00:00.000Z', finished_at: '2026-01-01T00:00:00.010Z',
      duration_ms: 10.0
    )
    @log.record_event(
      run_id: 'run-002', event_type: 'robot_run', robot_name: 'b',
      tool_name: nil, input: nil, output: nil, error_class: nil, error_message: nil,
      started_at: '2026-01-01T00:00:01.000Z', finished_at: '2026-01-01T00:00:01.010Z',
      duration_ms: 10.0
    )

    assert_equal 1, @log.events_for('run-001').size
    assert_equal 'a', @log.events_for('run-001').first[:robot_name]
    assert_equal 1, @log.events_for('run-002').size
    assert_equal 'b', @log.events_for('run-002').first[:robot_name]
  end

  def test_creates_db_directory_if_absent
    nested = File.join(@dir, 'deep', 'nested', 'audit.db')
    RobotLab::Audit::EventLog.new(db_path: nested)
    assert File.exist?(nested)
  end
end
