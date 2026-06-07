# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Audit', 'lib/robot_lab/audit'

  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "robot_lab"
require "robot_lab/audit"

require "minitest/autorun"
require "tmpdir"
