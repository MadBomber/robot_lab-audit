# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb', 'test/**/test_*.rb'].exclude('**/*_helper.rb')
  t.verbose = true
  t.ruby_opts << '-rtest_helper'
end

task default: :test

desc 'Run tests with verbose output'
task :test_verbose do
  ENV['TESTOPTS'] = '--verbose'
  Rake::Task[:test].invoke
end

desc 'Run a single test file'
task :test_file, [:file] do |_t, args|
  ruby "test/#{args[:file]}"
end

namespace :docs do
  desc 'Build MkDocs documentation'
  task :build do
    sh 'mkdocs build'
  end

  desc 'Serve MkDocs documentation locally on http://localhost:8000'
  task :serve do
    sh 'mkdocs serve'
  end
end
