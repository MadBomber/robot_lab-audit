# frozen_string_literal: true

require "securerandom"
require "json"

module RobotLab
  module Audit
    class Hook < RobotLab::Hook
      self.namespace = :audit

      class << self
        attr_accessor :event_log

        def before_network_run(ctx)
          return unless event_log

          set_run_id(SecureRandom.uuid)
          set_network_started_at(Time.now.utc)
        end

        def after_network_run(ctx)
          return unless event_log && current_run_id

          started  = current_network_started_at
          finished = Time.now.utc

          event_log.record_network_run(
            run_id:        current_run_id,
            network_name:  ctx.network&.name,
            input:         extract_network_input(ctx.context),
            result:        extract_network_result(ctx.result),
            error_class:   ctx.error&.class&.name,
            error_message: ctx.error&.message,
            started_at:    started&.iso8601(3),
            finished_at:   finished.iso8601(3),
            duration_ms:   started ? ((finished - started) * 1000).round(2) : nil
          )
        ensure
          clear_run_id
          clear_network_started_at
        end

        def before_run(ctx)
          ctx.local.started_at = Time.now.utc
        end

        def after_run(ctx)
          return unless event_log

          started  = ctx.local.started_at
          finished = Time.now.utc

          event_log.record_event(
            run_id:        current_run_id,
            event_type:    "robot_run",
            robot_name:    ctx.robot&.name,
            tool_name:     nil,
            input:         safe_json(ctx.request),
            output:        safe_json(ctx.response),
            error_class:   ctx.error&.class&.name,
            error_message: ctx.error&.message,
            started_at:    started&.iso8601(3),
            finished_at:   finished.iso8601(3),
            duration_ms:   started ? ((finished - started) * 1000).round(2) : nil
          )
        end

        def before_tool_call(ctx)
          ctx.local.started_at = Time.now.utc
        end

        def after_tool_call(ctx)
          return unless event_log

          started  = ctx.local.started_at
          finished = Time.now.utc

          event_log.record_event(
            run_id:        current_run_id,
            event_type:    "tool_call",
            robot_name:    ctx.robot&.name,
            tool_name:     ctx.tool_name,
            input:         safe_json(ctx.tool_args),
            output:        safe_json(ctx.tool_result),
            error_class:   ctx.tool_error&.class&.name,
            error_message: ctx.tool_error&.message,
            started_at:    started&.iso8601(3),
            finished_at:   finished.iso8601(3),
            duration_ms:   started ? ((finished - started) * 1000).round(2) : nil
          )
        end

        private

        def set_run_id(id)
          Thread.current[:robot_lab_audit_run_id] = id
        end

        def current_run_id
          Thread.current[:robot_lab_audit_run_id]
        end

        def clear_run_id
          Thread.current[:robot_lab_audit_run_id] = nil
        end

        def set_network_started_at(time)
          Thread.current[:robot_lab_audit_network_started_at] = time
        end

        def current_network_started_at
          Thread.current[:robot_lab_audit_network_started_at]
        end

        def clear_network_started_at
          Thread.current[:robot_lab_audit_network_started_at] = nil
        end

        def safe_json(value)
          return nil if value.nil?

          JSON.generate(value)
        rescue JSON::GeneratorError, TypeError
          value.inspect
        end

        # Extract a compact, serializable input string from a network run context hash.
        # Captures just the :message key if present; falls back to safe_json.
        def extract_network_input(context)
          return nil if context.nil?

          msg = context[:message] || context["message"]
          msg ? JSON.generate(msg) : safe_json(context)
        rescue
          context.inspect
        end

        # Extract a readable result string from a network run result.
        # Tries to pull the final robot reply; falls back to safe_json.
        def extract_network_result(result)
          return nil if result.nil?

          reply = result.value&.reply if result.respond_to?(:value)
          reply ? JSON.generate(reply) : safe_json(result)
        rescue
          result.inspect
        end
      end
    end
  end
end
