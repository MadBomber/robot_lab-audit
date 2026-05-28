# frozen_string_literal: true

require "logger"

require_relative "../../robot_lab/lib/robot_lab"
require_relative "../lib/robot_lab/audit"

RubyLLM.configure do |c|
  c.logger = Logger.new(File::NULL)
end

RobotLab.configure do |c|
  c.logger = Logger.new(File::NULL)
end

# ── Output helpers ─────────────────────────────────────────────────────────────

module ExOut
  WIDTH = 68
  RESET = "\e[0m"
  BOLD  = "\e[1m"
  DIM   = "\e[2m"
  CYAN  = "\e[36m"
  GREEN = "\e[32m"
  RED   = "\e[31m"
  GRAY  = "\e[90m"
end

def banner(title)
  puts
  puts "#{ExOut::BOLD}#{"=" * ExOut::WIDTH}#{ExOut::RESET}"
  puts "#{ExOut::BOLD} #{title}#{ExOut::RESET}"
  puts "#{ExOut::BOLD}#{"=" * ExOut::WIDTH}#{ExOut::RESET}"
  puts
end

def section(title)
  puts
  tail = "─" * [ExOut::WIDTH - title.length - 4, 2].max
  puts "#{ExOut::BOLD}#{ExOut::CYAN}── #{title} #{tail}#{ExOut::RESET}"
  puts
end

def hr
  puts "#{ExOut::DIM}#{"─" * ExOut::WIDTH}#{ExOut::RESET}"
end

def kv(label, value, color: ExOut::RESET)
  puts "  #{ExOut::BOLD}#{label.ljust(18)}#{ExOut::RESET}#{color}#{value}#{ExOut::RESET}"
end
