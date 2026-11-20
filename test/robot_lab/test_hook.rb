# frozen_string_literal: true

require 'test_helper'

class TestHook < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log = RobotLab::Audit::EventLog.new(db_path: File.join(@dir, 'audit.db'))
    RobotLab::Audit::Hook.event_log = @log
    Fiber[:robot_lab_audit_run_id] = nil
    Fiber[:robot_lab_audit_network_started_at] = nil
  end

  def teardown
    RobotLab::Audit::Hook.event_log = nil
    Fiber[:robot_lab_audit_run_id] = nil
    Fiber[:robot_lab_audit_network_started_at] = nil
    FileUtils.rm_rf(@dir)
  end

  # --- network run ---

  def test_before_network_run_sets_thread_local_run_id
    ctx = stub_network_run_ctx
    RobotLab::Audit::Hook.before_network_run(ctx)
    refute_nil Fiber[:robot_lab_audit_run_id]
  end

  def test_after_network_run_records_row_and_clears_thread_locals
    ctx = stub_network_run_ctx(result: 'done')
    RobotLab::Audit::Hook.before_network_run(ctx)
    RobotLab::Audit::Hook.after_network_run(ctx)

    runs = @log.network_runs
    assert_equal 1, runs.size
    assert_equal 'test_network', runs.first[:network_name]
    assert_equal '"done"', runs.first[:result]
    assert_nil Fiber[:robot_lab_audit_run_id]
    assert_nil Fiber[:robot_lab_audit_network_started_at]
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
    Fiber[:robot_lab_audit_run_id] = 'run-abc'
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
    Fiber[:robot_lab_audit_run_id] = 'run-abc'
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

  # --- on_error ---

  def test_on_error_records_failed_robot_run
    ctx = stub_run_ctx(request: 'hello', error: RuntimeError.new('robot boom'))
    simulate_hook_dispatch(ctx) do
      RobotLab::Audit::Hook.before_run(ctx)
      RobotLab::Audit::Hook.on_error(ctx)
    end

    event = @log.recent_errors.first
    assert_equal 'robot_run',    event[:event_type]
    assert_equal 'RuntimeError', event[:error_class]
    assert_equal 'robot boom',   event[:error_message]
    refute_nil event[:duration_ms]
  end

  def test_on_error_records_failed_network_run_and_clears_run_id
    ctx = stub_network_run_ctx(error: RuntimeError.new('network boom'))
    RobotLab::Audit::Hook.before_network_run(ctx)
    RobotLab::Audit::Hook.on_error(ctx)

    run = @log.network_runs.first
    assert_equal 'RuntimeError', run[:error_class]
    assert_equal 'network boom', run[:error_message]
    assert_nil Fiber[:robot_lab_audit_run_id]
  end

  def test_on_error_ignores_task_contexts
    ctx = RobotLab::TaskHookContext.new(task: FakeTask.new('test_task', FakeRobot.new('test_robot')), error: RuntimeError.new('task boom'))
    RobotLab::Audit::Hook.on_error(ctx)

    assert_empty @log.recent_errors
    assert_empty @log.network_runs
  end

  def test_hooks_run_records_a_raising_robot_run
    registry = RobotLab::HookRegistry.new
    registry.on(RobotLab::Audit::Hook)
    ctx = stub_run_ctx(request: 'hello')

    assert_raises(RuntimeError) do
      RobotLab::Hooks.run(:run, ctx, registries: [registry]) { raise 'robot boom' }
    end

    assert_equal 'robot boom', @log.recent_errors.first[:error_message]
  end

  # --- run id propagation ---

  def test_run_id_is_inherited_by_threads_and_fibers_started_during_the_run
    RobotLab::Audit::Hook.before_network_run(stub_network_run_ctx)
    run_id = Fiber[:robot_lab_audit_run_id]

    assert_equal run_id, Thread.new { Fiber[:robot_lab_audit_run_id] }.value
    assert_equal run_id, Fiber.new { Fiber[:robot_lab_audit_run_id] }.resume
  end

  # --- safe_json ---

  def test_safe_json_falls_back_to_inspect_for_circular_references
    circular = []
    circular << circular

    assert_equal circular.inspect, RobotLab::Audit::Hook.send(:safe_json, circular)
  end

  def test_safe_json_falls_back_to_inspect_for_nan
    assert_equal 'NaN', RobotLab::Audit::Hook.send(:safe_json, Float::NAN)
  end

  # --- enable ---

  def test_enable_registers_the_hook_only_once
    saved = RobotLab.hooks
    RobotLab.clear_hooks!
    2.times { RobotLab::Audit.enable(db_path: File.join(@dir, 'enabled.db')) }

    handlers = RobotLab.hooks.registrations.map(&:handler_class)
    assert_equal [RobotLab::Audit::Hook], handlers
  ensure
    RobotLab.instance_variable_set(:@hooks, saved)
  end

  FakeRobot   = Struct.new(:name)
  FakeNetwork = Struct.new(:name)
  FakeTool    = Struct.new(:name)
  FakeTask    = Struct.new(:name, :robot)

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
