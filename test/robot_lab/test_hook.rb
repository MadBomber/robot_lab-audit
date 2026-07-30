# frozen_string_literal: true

require 'test_helper'

class TestHook < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log = RobotLab::Audit::EventLog.new(db_path: File.join(@dir, 'audit.db'))
    RobotLab::Audit::Hook.event_log = @log
    Thread.current[:robot_lab_audit_run_id] = nil
    Thread.current[:robot_lab_audit_network_started_at] = nil
  end

  def teardown
    RobotLab::Audit::Hook.event_log = nil
    Thread.current[:robot_lab_audit_run_id] = nil
    Thread.current[:robot_lab_audit_network_started_at] = nil
    FileUtils.rm_rf(@dir)
  end

  # --- network run ---

  def test_before_network_run_sets_thread_local_run_id
    ctx = stub_network_run_ctx
    RobotLab::Audit::Hook.before_network_run(ctx)
    refute_nil Thread.current[:robot_lab_audit_run_id]
  end

  def test_after_network_run_records_row_and_clears_thread_locals
    ctx = stub_network_run_ctx(result: 'done')
    RobotLab::Audit::Hook.before_network_run(ctx)
    RobotLab::Audit::Hook.after_network_run(ctx)

    runs = @log.network_runs
    assert_equal 1, runs.size
    assert_equal 'test_network', runs.first[:network_name]
    assert_equal '"done"', runs.first[:result]
    assert_nil Thread.current[:robot_lab_audit_run_id]
    assert_nil Thread.current[:robot_lab_audit_network_started_at]
  end

  def test_after_network_run_records_error
    ctx = stub_network_run_ctx(error: RuntimeError.new('boom'))
    RobotLab::Audit::Hook.before_network_run(ctx)
    RobotLab::Audit::Hook.after_network_run(ctx)

    run = @log.network_runs.first
    assert_equal 'RuntimeError', run[:error_class]
    assert_equal 'boom',         run[:error_message]
  end

  def test_after_network_run_skips_when_no_run_id
    ctx = stub_network_run_ctx
    RobotLab::Audit::Hook.after_network_run(ctx)
    assert_empty @log.network_runs
  end

  # --- robot run ---

  def test_before_run_sets_started_at_on_local
    ctx = stub_run_ctx
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_run(ctx)
      refute_nil ctx.local.started_at
    end
  end

  def test_after_run_records_robot_run_event
    ctx = stub_run_ctx(request: 'hello', response: 'world')
    Thread.current[:robot_lab_audit_run_id] = 'run-abc'
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_run(ctx)
      RobotLab::Audit::Hook.after_run(ctx)
    end

    events = @log.events_for('run-abc')
    assert_equal 1, events.size
    assert_equal 'robot_run',  events.first[:event_type]
    assert_equal 'test_robot', events.first[:robot_name]
    assert_equal '"hello"',    events.first[:input]
    assert_equal '"world"',    events.first[:output]
  end

  # --- tool call ---

  def test_before_tool_call_sets_started_at_on_local
    ctx = stub_tool_call_ctx
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_tool_call(ctx)
      refute_nil ctx.local.started_at
    end
  end

  def test_after_tool_call_records_tool_call_event
    ctx = stub_tool_call_ctx(tool_name: 'my_tool', tool_args: { x: 1 }, tool_result: 'ok')
    Thread.current[:robot_lab_audit_run_id] = 'run-abc'
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_tool_call(ctx)
      RobotLab::Audit::Hook.after_tool_call(ctx)
    end

    events = @log.events_for('run-abc')
    assert_equal 1, events.size
    event = events.first
    assert_equal 'tool_call', event[:event_type]
    assert_equal 'my_tool',   event[:tool_name]
    assert_equal '{"x":1}',   event[:input]
    assert_equal '"ok"',      event[:output]
  end

  def test_no_event_log_is_a_noop
    RobotLab::Audit::Hook.event_log = nil
    ctx = stub_run_ctx
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_run(ctx)
      RobotLab::Audit::Hook.after_run(ctx)
    end
    assert_empty @log.events_for(nil)
  end

  FakeRobot   = Struct.new(:name)
  FakeNetwork = Struct.new(:name)
  FakeTool    = Struct.new(:name)

  private

  def stub_network_run_ctx(result: nil, error: nil)
    ctx = RobotLab::NetworkRunHookContext.new(
      network: FakeNetwork.new('test_network'),
      context: 'test input',
      result: result,
      error: error
    )
    ctx.result = result
    ctx.error  = error
    ctx
  end

  def stub_run_ctx(request: 'req', response: nil, error: nil)
    ctx = RobotLab::RunHookContext.new(
      robot: FakeRobot.new('test_robot'),
      request: request,
      response: response,
      error: error
    )
    ctx.response = response
    ctx.error    = error
    ctx
  end

  def stub_tool_call_ctx(tool_name: 'tool', tool_args: {}, tool_result: nil, tool_error: nil)
    tool = FakeTool.new(tool_name)
    ctx  = RobotLab::ToolCallHookContext.new(
      tool: tool,
      tool_args: tool_args,
      robot: FakeRobot.new('test_robot'),
      tool_result: tool_result,
      tool_error: tool_error
    )
    ctx.tool_result = tool_result
    ctx.tool_error  = tool_error
    ctx
  end

  # Simulates the namespace activation that HookRegistry normally provides,
  # so ctx.local works inside hook methods.
  def simulate_hook_dispatch(ctx, &)
    ctx.with_namespace(:audit, &)
  end
end
