# frozen_string_literal: true

require_relative 'audit/version'
require_relative 'audit/event_log'

module RobotLab
  module Audit
    class Error < StandardError; end

    # Configure the audit hook with a SQLite database path and register it globally.
    #
    # @param db_path [String] path to the SQLite database file (created if absent)
    #
    # @example
    #   RobotLab::Audit.enable(db_path: "~/.robot_lab/audit.db")
    def self.enable(db_path:)
      unless defined?(RobotLab::Audit::Hook)
        raise Error, 'robot_lab must be loaded before calling RobotLab::Audit.enable'
      end

      Hook.event_log = EventLog.new(db_path: db_path)
      RobotLab.on(Hook)
    end
  end
end

require_relative 'audit/hook' if defined?(RobotLab::Hook)

if defined?(RobotLab) && RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:audit, RobotLab::Audit)
end
