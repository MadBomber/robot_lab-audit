# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'fileutils'

module RobotLab
  module Audit
    class EventLog
      SCHEMA = <<~SQL
        CREATE TABLE IF NOT EXISTS network_runs (
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

        CREATE TABLE IF NOT EXISTS audit_events (
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
      SQL

      def initialize(db_path:)
        path = File.expand_path(db_path.to_s)
        FileUtils.mkdir_p(File.dirname(path))
        @db = SQLite3::Database.new(path)
        @db.execute_batch(SCHEMA)
      end

      def record_network_run(run_id:, network_name:, input:, result:, error_class:,
                             error_message:, started_at:, finished_at:, duration_ms:)
        @db.execute(
          "INSERT INTO network_runs
             (run_id, network_name, input, result, error_class, error_message,
              started_at, finished_at, duration_ms)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [run_id, network_name, input, result, error_class, error_message,
           started_at, finished_at, duration_ms]
        )
      end

      def record_event(run_id:, event_type:, robot_name:, tool_name:, input:, output:,
                       error_class:, error_message:, started_at:, finished_at:, duration_ms:)
        @db.execute(
          "INSERT INTO audit_events
             (run_id, event_type, robot_name, tool_name, input, output,
              error_class, error_message, started_at, finished_at, duration_ms)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [run_id, event_type, robot_name, tool_name, input, output,
           error_class, error_message, started_at, finished_at, duration_ms]
        )
      end

      def network_runs(limit: 100)
        rows = @db.execute('SELECT * FROM network_runs ORDER BY started_at DESC LIMIT ?', [limit])
        rows.map { |r| row_to_hash(:network_runs, r) }
      end

      def events_for(run_id)
        rows = @db.execute('SELECT * FROM audit_events WHERE run_id = ? ORDER BY started_at', [run_id])
        rows.map { |r| row_to_hash(:audit_events, r) }
      end

      def recent_errors(limit: 50)
        rows = @db.execute(
          'SELECT * FROM audit_events WHERE error_class IS NOT NULL ORDER BY started_at DESC LIMIT ?',
          [limit]
        )
        rows.map { |r| row_to_hash(:audit_events, r) }
      end

      NETWORK_RUN_COLUMNS = %i[id run_id network_name input result error_class
                               error_message started_at finished_at duration_ms].freeze
      AUDIT_EVENT_COLUMNS = %i[id run_id event_type robot_name tool_name input output
                               error_class error_message started_at finished_at duration_ms].freeze

      private

      def row_to_hash(table, row)
        cols = table == :network_runs ? NETWORK_RUN_COLUMNS : AUDIT_EVENT_COLUMNS
        cols.zip(row).to_h
      end
    end
  end
end
