# frozen_string_literal: true

require 'securerandom'
require 'json'

module RobotLab
  module Audit
    # :reek:RepeatedConditional -- each callback independently no-ops when
    # event_log is nil, so the hook can be registered globally (RobotLab.on)
    # before Audit.enable ever runs, or scoped to one robot/network without
    # ever calling enable at all. A Null Object would remove the repeated
    # check but couples every caller to a different `Hook.event_log` contract
    # (an object always present vs. nil-means-disabled); not worth it here.
    class Hook < RobotLab::Hook
      self.namespace = :audit

      class << self
        attr_accessor :event_log

        def before_network_run(_ctx)
          return unless event_log

          set_run_id(SecureRandom.uuid)
          set_network_started_at(Time.now.utc)
        end

        def after_network_run(ctx)
          record_network_run(ctx)
        end

        def before_run(ctx)
          ctx.local.started_at = Time.now.utc
        end

        def after_run(ctx)
          record_robot_run(ctx)
        end

        def before_tool_call(ctx)
          ctx.local.started_at = Time.now.utc
        end

        def after_tool_call(ctx)
          return unless event_log

          record_audit_event(
            'tool_call', ctx, ctx.local.started_at,
            ctx.tool_name, safe_json(ctx.tool_args), safe_json(ctx.tool_result), ctx.tool_error
          )
        end

        # Core skips the after_* hooks when a run raises and calls on_error
        # instead, for the run, network_run and task families. Without this
        # callback a failed robot or network run would leave no row at all.
        # Task failures are not recorded separately: the robot run inside the
        # task already was.
        def on_error(ctx)
          case ctx
          when RobotLab::NetworkRunHookContext then record_network_run(ctx)
          when RobotLab::RunHookContext        then record_robot_run(ctx)
          end
        end

        private

        def record_network_run(ctx)
          return unless event_log && current_run_id

          event_log.record_network_run(
            run_id:       current_run_id,
            network_name: ctx.network&.name,
            input:        extract_network_input(ctx.context),
            result:       extract_network_result(ctx.result),
            **error_fields(ctx.error),
            **timing(current_network_started_at)
          )
        ensure
          clear_run_id
          clear_network_started_at
        end

        def record_robot_run(ctx)
          return unless event_log

          record_audit_event(
            'robot_run', ctx, ctx.local.started_at,
            nil, safe_json(ctx.request), safe_json(ctx.response), ctx.error
          )
        end

        # :reek:LongParameterList -- private helper with exactly two call
        # sites, each passing every argument explicitly; a wrapper object
        # would add indirection without making either call site clearer.
        def record_audit_event(event_type, ctx, started, tool_name, input, output, error)
          event_log.record_event(
            run_id:     current_run_id,
            event_type: event_type,
            robot_name: ctx.robot&.name,
            tool_name:  tool_name,
            input:      input,
            output:     output,
            **error_fields(error),
            **timing(started)
          )
        end

        def timing(started)
          finished = Time.now.utc
          {
            started_at:  started&.iso8601(3),
            finished_at: finished.iso8601(3),
            duration_ms: started ? ((finished - started) * 1000).round(2) : nil
          }
        end

        def error_fields(err)
          {
            error_class:   err&.class&.name,
            error_message: err&.message
          }
        end

        # The run id lives in fiber storage (Fiber[]), not Thread.current[]:
        # fiber storage is copied into every Fiber and Thread created while
        # it is set, so robots that a network runs concurrently still log
        # under the network's run id. Thread.current[] is per-fiber and is
        # not inherited, which left those rows with a NULL run_id.
        def set_run_id(id)
          Fiber[:robot_lab_audit_run_id] = id
        end

        def current_run_id
          Fiber[:robot_lab_audit_run_id]
        end

        def clear_run_id
          Fiber[:robot_lab_audit_run_id] = nil
        end

        def set_network_started_at(time)
          Fiber[:robot_lab_audit_network_started_at] = time
        end

        def current_network_started_at
          Fiber[:robot_lab_audit_network_started_at]
        end

        def clear_network_started_at
          Fiber[:robot_lab_audit_network_started_at] = nil
        end

        # JSON::JSONError covers GeneratorError (NaN, Infinity) and
        # NestingError (circular references).
        def safe_json(value)
          return nil if value.nil?

          JSON.generate(value)
        rescue JSON::JSONError, TypeError
          value.inspect
        end

        def extract_network_input(context)
          return nil if context.nil?

          msg = context[:message] || context['message']
          msg ? JSON.generate(msg) : safe_json(context)
        rescue StandardError
          context.inspect
        end

        def extract_network_result(result)
          return nil if result.nil?

          reply = result.value&.reply if result.respond_to?(:value)
          reply ? JSON.generate(reply) : safe_json(result)
        rescue StandardError
          result.inspect
        end
      end
    end
  end
end
