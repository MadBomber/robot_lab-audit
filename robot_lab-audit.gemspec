# frozen_string_literal: true

require_relative 'lib/robot_lab/audit/version'

Gem::Specification.new do |spec|
  spec.name = 'robot_lab-audit'
  spec.version = RobotLab::Audit::VERSION
  spec.authors = ['Dewayne VanHoozer']
  spec.email = ['dvanhoozer@gmail.com']

  spec.summary = 'SQLite-backed execution audit log for RobotLab via the Hook system.'
  spec.description = 'Appends structured records for network runs, robot invocations, and tool calls ' \
                     'to a SQLite database for post-mortem analysis.'
  spec.homepage = 'https://github.com/MadBomber/robot_lab-audit'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'robot_lab', '>= 0.1'
  spec.add_dependency 'sqlite3', '~> 2.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
