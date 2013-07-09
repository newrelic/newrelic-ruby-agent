#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# this is to make sure that the Multiverse environment loads with the
# the gem version of Minitest (necessary for Rails 4) and not the one
# in standard library.
if defined?(gem)
  gem 'minitest'
end

require File.expand_path(File.join(File.dirname(__FILE__), 'environment'))
module Multiverse
  class Suite
    include Color
    attr_accessor :directory, :include_debugger
    def initialize(directory, include_debugger=nil)
      self.directory = directory
      self.include_debugger = !!include_debugger
    end

    def clean_gemfiles
      FileUtils.rm_rf File.join(directory, 'Gemfile')
      FileUtils.rm_rf File.join(directory, 'Gemfile.lock')
    end


    def environments
      @environments ||= (
        Dir.chdir directory
        Envfile.new(File.join(directory, 'Envfile'))
      )
    end

    # load the environment for this suite after we've forked
    def load_dependencies(gemfile_text)
      clean_gemfiles
      begin
        generate_gemfile(gemfile_text)
        bundle
      rescue => e
        puts "#{e.class}: #{e}"
        puts "Fast local bundle failed.  Attempting to install from rubygems.org"
        clean_gemfiles
        generate_gemfile(gemfile_text, false)
        bundle
      end
      print_environment
    end

    def bundle
      require 'rubygems'
      require 'bundler'
      bundler_out = `bundle`
      puts bundler_out if verbose? || $? != 0
      raise "bundle command failed with (#{$?})" unless $? == 0
      Bundler.require

      # Ensure mocha is loaded after the test framework by deferring until here
      # see: http://gofreerange.com/mocha/docs/
      unless environments.omit_mocha
        if RUBY_VERSION > '1.8.7'
          require 'mocha/setup'
        else
          require 'mocha'
        end
      end
    end

    def generate_gemfile(gemfile_text, local = true)
      gemfile = File.join(Dir.pwd, 'Gemfile')
      File.open(gemfile,'w') do |f|
        f.puts '  source :rubygems' unless local
        f.print gemfile_text
        f.puts newrelic_gemfile_line unless gemfile_text =~ /^\s*gem .newrelic_rpm./
        f.puts jruby_openssl_line unless gemfile_text =~ /^\s*gem .jruby-openssl./
        if RUBY_VERSION > '1.8.7'
          f.puts "  gem 'test-unit', :require => 'test/unit'"
          f.puts "  gem 'debugger'" if include_debugger
          f.puts "  gem 'mocha', '~> 0.13.0', :require => false" unless environments.omit_mocha
        else
          f.puts "  gem 'ruby-debug'" if include_debugger
          f.puts "  gem 'mocha', '~> 0.9.8', :require => false" unless environments.omit_mocha
        end
      end
      puts yellow("Gemfile set to:") if verbose?
      puts File.open(gemfile).read if verbose?
    end

    def newrelic_gemfile_line
      line = ENV['NEWRELIC_GEMFILE_LINE'] if ENV['NEWRELIC_GEMFILE_LINE']
      path = ENV['NEWRELIC_GEM_PATH'] || '../../../..'
      line ||= "  gem 'newrelic_rpm', :path => '#{path}'"
      line += ", #{environments.newrelic_gemfile_options}" if environments.newrelic_gemfile_options
      line
    end

    def jruby_openssl_line
      "gem 'jruby-openssl', :require => false, :platforms => [:jruby]"
    end

    def print_environment
      puts yellow("Environment loaded with:") if verbose?
      gems = Bundler.definition.specs.inject([]) do |m, s|
        next m if s.name == 'bundler'
        m.push "#{s.name} (#{s.version})"
        m
      end.sort
      puts(gems.join(', '))
    end

    def execute_child_environment(env_index)
      gemfile_text = environments[env_index]
      load_dependencies(gemfile_text)
      execute_ruby_files
      trigger_test_unit
    end

    # Load the test suite's environment and execute it.
    #
    # Normally we fork to do this, and wait for the child to exit, to avoid
    # polluting the parent process with test dependencies.  JRuby doesn't
    # implement #fork so we resort to a hack.  We exec this lib file, which
    # loads a new JVM for the tests to run in.
    def execute
      if environments.condition && !environments.condition.call
        puts yellow("SKIPPED #{directory.inspect}: #{environments.skip_message}")
        return
      end
      puts yellow("\nRunning #{directory.inspect} in #{environments.size} environments")
      environments.before.call if environments.before
      environments.each_with_index do |gemfile_text, i|
        with_clean_env do
          execute_with_pipe(i)
        end
      end
      environments.after.call if environments.after
    end

    def with_clean_env
      if defined?(Bundler)
        # clear $BUNDLE_GEMFILE and $RUBYOPT so that the ruby subprocess can run
        # in the context of another bundle.
        Bundler.with_clean_env { yield }
      else
        yield
      end
    end

    def execute_with_pipe(env)
      OutputCollector.buffers.push('')
      puts yellow("Running #{directory.inspect} for Envfile entry #{env}")
      IO.popen("#{__FILE__} #{directory} #{env}") do |io|
        puts yellow("Starting tests in child PID #{io.pid}")
        while chars = io.read(8) do
          OutputCollector.buffers.last << chars
          print chars
        end
      end
      if $? != 0
        OutputCollector.failing_output.push(OutputCollector.buffers.last)
      end
      Multiverse::Runner.notice_exit_status $?
    end

    # something makes Test::Unit not want to run automatically.  Seems like the
    # at_exit hook may be failing to run due to forking.
    def trigger_test_unit
      case
      when defined? Test::Unit::RunCount # 1.9.3
        # JRuby 1.7 doesn't seem to have a problem triggering test unit.  In
        # contrast to MRI triggering it like this causes an error.
        return if defined?(JRuby)

        Test::Unit::RunCount.run_once do
          exit(Test::Unit::Runner.new.run || true)
        end
      when defined? MiniTest::Unit # 1.9.2
        exit(MiniTest::Unit.new.run)
      when defined? Test::Unit::AutoRunner # 1.8.7
        exit(Test::Unit::AutoRunner.run)
      else
        raise "Can't figure out how to trigger Test::Unit"
      end
    end

    def execute_ruby_files
      Dir.chdir directory
      Dir[File.join(directory, '*.rb')].each do |file|
        puts yellow("Executing #{file.inspect}") if verbose?
        load file
      end
    end

    def verbose?
      ENV['VERBOSE']
    end
  end
end

# Exectute the suite.  We need this if we want to execute a suite by spawning a
# new process instead of forking.
if $0 == __FILE__
  # Redirect stderr to stdout so that we can capture both in the popen that
  # feeds into the OutputCollector above.
  $stderr.reopen($stdout)
  Multiverse::Suite.new(ARGV[0], ARGV[2]).execute_child_environment(ARGV[1].to_i)
end
