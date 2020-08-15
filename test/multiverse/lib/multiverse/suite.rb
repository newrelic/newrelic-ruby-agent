#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# This makes sure that the Multiverse environment loads with the gem
# version of Minitest, which we use throughout, not the one in stdlib on
# Rubies starting with 1.9.x
require 'rubygems'
require 'base64'
require 'fileutils'
require 'digest'

require File.expand_path '../../multiverse', __FILE__
require File.expand_path '../shell_utils', __FILE__

module Multiverse
  class Suite
    include Color
    attr_accessor :directory, :opts

    def initialize(directory, opts={})
      self.directory  = File.expand_path directory
      self.opts       = opts
      ENV["VERBOSE"]  = '1' if opts[:verbose]
    end

    def self.encode_options(decoded_opts)
      Base64.encode64(Marshal.dump(decoded_opts)).gsub("\n", "")
    end

    def self.decode_options(encoded_opts)
      Marshal.load(Base64.decode64(encoded_opts))
    end

    def suite
      File.basename(directory)
    end

    def seed
      opts.fetch(:seed, "")
    end

    def debug
      opts.fetch(:debug, false)
    end

    def names
      opts.fetch(:names, [])
    end

    def use_cache?
      !opts.fetch(:nocache, false)
    end

    def filter_env
      value = opts.fetch(:env, nil)
      value = value.to_i if value
    end

    def filter_file
      opts.fetch(:file, nil)
    end

    def clean_gemfiles(env_index)
      gemfiles = ["Gemfile.#{env_index}", "Gemfile.#{env_index}.lock"]
      gemfiles.each {|f| File.delete(f) if File.exist?(f)}
    end

    def envfile_path
      ep = File.expand_path 'Envfile'
      if !File.exist?(ep)
        ep = File.expand_path 'Envfile', directory
        raise "#{ep} not found" unless File.exist?(ep)
      end
      ep
    end

    def environments
      @environments ||= (
        Dir.chdir directory
        Envfile.new(envfile_path)
      )
    end

    # load the environment for this suite after we've forked
    def load_dependencies(gemfile_text, env_index, should_print=true)
      ENV["BUNDLE_GEMFILE"] = "Gemfile.#{env_index}"
      clean_gemfiles(env_index)
      begin
        generate_gemfile(gemfile_text, env_index)
        ensure_bundle(env_index)
      rescue => e
        if verbose?
          puts "#{e.class}: #{e}"
          puts e.backtrace
          puts "Fast local bundle failed.  Attempting to install from rubygems.org"
        end
        clean_gemfiles(env_index)
        generate_gemfile(gemfile_text, env_index, false)
        ensure_bundle(env_index)
      end
      print_environment if should_print
    end

    def with_potentially_mismatched_bundler
      yield
    rescue Bundler::LockfileError => error
      raise if @retried
      if verbose?
        puts "Encountered Bundler error: #{error.message}"
        puts "Currently Active Bundler Version: #{Bundler::VERSION}"
      end
      change_lock_version(`pwd`, ENV["BUNDLE_GEMFILE"])
      @retried = true
      retry
    end

    def bundling_lock_file
      with_potentially_mismatched_bundler do
        File.join(Bundler.bundle_path, 'multiverse-bundler.lock')
      end
    end

    def bundler_cache_dir
      with_potentially_mismatched_bundler do
        File.join(Bundler.bundle_path, 'multiverse-cache')
      end
    end

    # Ensures we bundle will recognize an explicit version number on command line
    def safe_explicit version
      return version if version.to_s == ""
      test_version = `bundle #{version} --version` =~ /Could not find command/
      test_version ? "" : version
    end

    def explicit_bundler_version dir
      return if RUBY_VERSION.to_f < 2.3
      fn = File.join(dir, ".bundler-version")
      version = File.exist?(fn) ? File.read(fn).chomp.to_s.strip : nil
      safe_explicit(version.to_s == "" ? nil : "_#{version}_")
    end

    def bundle_show_env bundle_cmd
      return unless ENV["BUNDLE_SHOW_ENV"]
      puts `#{bundle_cmd} env` 
    end

    def bundle_config dir, bundle_cmd
      `cd #{dir} && #{bundle_cmd} config build.nokogiri --use-system-libraries`
    end

    def bundle_install(dir, exact_version=nil)
      puts "Bundling in #{dir}..."
      bundler_version = exact_version || explicit_bundler_version(dir)
      bundle_cmd = "bundle #{explicit_bundler_version(dir)}".strip
      bundle_config dir, bundle_cmd
      bundle_show_env bundle_cmd
      full_bundle_cmd = "#{bundle_cmd} install"
      result = ShellUtils.try_command_n_times full_bundle_cmd, 3
      unless $?.success?
        puts "Failed local bundle, trying again without the version lock..."
        change_lock_version(dir, ENV["BUNDLE_GEMFILE"])
        result = ShellUtils.try_command_n_times full_bundle_cmd, 3
      end

      result = red(result) unless $?.success?
      puts result
      $?
    end

    def change_lock_version filepath, gemfile, new_version=Bundler::VERSION
      begin
        lock_filename = "#{filepath}/#{gemfile}.lock".gsub(/\n|\r/,'')
      rescue => e
        puts "ERROR: #{e.inspect}"
        puts "ERROR: on lock_filename #{filepath.inspect} / #{gemfile.inspect}"
        raise
      end
      return unless File.exist? lock_filename

      lock_contents = File.read(lock_filename).split("\n")
      old_version = lock_contents.pop.strip

      lock_contents << "   #{new_version}"
      File.open(lock_filename, 'w'){|f| f.puts lock_contents}

      if verbose?
        puts "Changing the Bundler version lock in #{lock_filename}"
        puts "  Changed: #{old_version} to #{new_version}"
      end
    end

    # Running the bundle should only happen one at a time per Ruby version or
    # we occasionally get compilation errors. With the groups and parallelizing
    # things out more, this is more of an issue, so start locking it down.
    def exclusive_bundle
      bundler_out = nil
      File.open(bundling_lock_file, File::RDWR|File::CREAT) do |f|
        puts "Waiting on '#{bundling_lock_file}' for our chance to bundle" if verbose?
        f.flock(File::LOCK_EX)
        puts "Let's get ready to BUNDLE!" if verbose?

        bundler_out = bundle_install(`pwd`.chomp!)
      end
      bundler_out
    end

    def ensure_bundle(env_index)
      require 'rubygems'
      require 'bundler'
      if use_cache?
        ensure_bundle_cached(env_index) || ensure_bundle_uncached(env_index)
      else
        ensure_bundle_uncached(env_index)
      end
      with_potentially_mismatched_bundler do
        Bundler.require
      end
    end

    def envfile_hash
      Digest::MD5.hexdigest(File.read(envfile_path))
    end

    def cached_gemfile_lock_filename(env_index)
      "Gemfile.#{suite}.#{env_index}.#{envfile_hash}.lock"
    end

    def ensure_bundle_cached(env_index)
      cache_dir = bundler_cache_dir
      FileUtils.mkdir_p(cache_dir)
      filename = cached_gemfile_lock_filename(env_index)
      path = File.join(cache_dir, filename)

      if File.exist?(path)
        dst_path = File.join(directory, "Gemfile.#{env_index}.lock")
        puts "Using cached Gemfile.lock from #{path} at #{dst_path}" if verbose?
        FileUtils.cp(path, dst_path)
        true
      else
        false
      end
    end

    def ensure_bundle_uncached(env_index)
      bundler_out = exclusive_bundle
      puts bundler_out if verbose? || $? != 0
      raise "bundle command failed with (#{$?})" unless $? == 0
    end

    def generate_gemfile(gemfile_text, env_index, local = true)
      pin_rack_version_if_needed(gemfile_text)

      gemfile = File.join(Dir.pwd, "Gemfile.#{env_index}")
      File.open(gemfile,'w') do |f|
        f.puts 'source "https://rubygems.org"'
        f.print gemfile_text
        f.puts newrelic_gemfile_line unless gemfile_text =~ /^\s*gem .newrelic_rpm./
        f.puts jruby_openssl_line unless gemfile_text =~ /^\s*gem .jruby-openssl./ || (defined?(JRUBY_VERSION) && JRUBY_VERSION > '1.7')
        f.puts minitest_line unless gemfile_text =~ /^\s*gem .minitest[^_]./
        f.puts "gem 'rake'" unless gemfile_text =~ /^\s*gem .rake[^_]./ || suite == 'rake'

        f.puts "gem 'mocha', '~> 1.9.0', :require => false"

        if debug
          f.puts "gem 'pry', '~> 0.10.0'"
          f.puts "gem 'pry-nav'"
          f.puts "gem 'pry-stack_explorer', platforms: :mri"
        end
      end
      if verbose?
        puts "Ruby: #{RUBY_VERSION}  Platform: #{RUBY_PLATFORM} RubyGems: #{Gem::VERSION}"
        puts yellow("Gemfile.#{env_index} set to:")
        puts File.open(gemfile).read
      end
    end

    def newrelic_gemfile_line
      line = ENV['NEWRELIC_GEMFILE_LINE'] if ENV['NEWRELIC_GEMFILE_LINE']
      path = ENV['NEWRELIC_GEM_PATH'] || '../../../..'
      line ||= "gem 'newrelic_rpm', :path => '#{path}'"
      line
    end

    def jruby_openssl_line
      "gem 'jruby-openssl', '~> 0.9.10', :require => false, :platforms => [:jruby]"
    end

    def minitest_line
      "gem 'minitest', '~> #{minitest_version}', :require => false"
    end

    def minitest_version
      case
      when RUBY_VERSION >= '2.4'
        '5.10.1'
      else
        '4.7.5'
      end
    end

    def require_minitest
      require 'minitest'
    rescue LoadError
      require 'minitest/unit'
    end

    # Rack 2.0 works with Ruby > 2.2.2. Earlier rubies need to pin
    # their Rack version prior to 2.0
    def pin_rack_version_if_needed gemfile_text
      return if suite == "rack"
      rx = /^\s*?gem\s*?('|")rack('|")\s*?$/
      if gemfile_text =~ rx && RUBY_VERSION < "2.2.2"
        gemfile_text.gsub! rx, 'gem "rack", "< 2.0.0"'
      end
    end

    def print_environment
      puts yellow("Environment loaded with:") if verbose?
      gems = with_potentially_mismatched_bundler do
        Bundler.definition.specs.inject([]) do |m, s|
          next m if s.name == 'bundler'
          m.push "#{s.name} (#{s.version})"
          m
        end
      end.sort
      puts(gems.join(', '))
    end

    def execute_child_environment(env_index)
      with_unbundled_env do
        ENV["MULTIVERSE_ENV"] = env_index.to_s
        log_test_running_process
        configure_before_bundling

        gemfile_text = environments[env_index]

        load_dependencies(gemfile_text, env_index)

        configure_child_environment
        execute_ruby_files
        trigger_test_run
      end
    end

    def log_test_running_process
      puts yellow("Starting tests in child PID #{Process.pid} at #{Time.now}\n")
    end

    def should_serialize?
      ENV['SERIALIZE'] || debug
    end

    def check_environment_condition
      if environments.condition && !environments.condition.call
        puts yellow("SKIPPED #{directory.inspect}: #{environments.skip_message}")
        false
      else
        true
      end
    end

    def prime
      ENV["VERBOSE"]= "1"
      return unless check_environment_condition

      puts yellow("\nPriming #{directory.inspect}")
      @environments = nil

      environments.each_with_index do |gemfile_text, env_index|
        puts yellow("... for Envfile entry #{env_index}")
        with_unbundled_env do
          load_dependencies(gemfile_text, env_index, false)
        end
      end
    end

    # Load the test suite's environment and execute it.
    #
    # Normally we fork to do this, and wait for the child to exit, to avoid
    # polluting the parent process with test dependencies.  JRuby doesn't
    # implement #fork so we resort to a hack.  We exec this lib file, which
    # loads a new JVM for the tests to run in.
    def execute
      return unless check_environment_condition

      label = should_serialize? ? 'serial' : 'parallel'
      env_count = filter_env ? 1 : environments.size
      puts yellow("\nRunning #{directory.inspect} in #{env_count} environments in #{label}")

      environments.before.call if environments.before
      if should_serialize?
        execute_serial
      else
        execute_parallel
      end
      environments.after.call if environments.after
    rescue => e
      puts red("Failure during execution of suite #{directory.inspect}.")
      puts red("This typically is a result of a Ruby failure in your Envfile.")
      puts
      puts red(e.class)
      puts red(e.message)
      exit(1)
    end

    def execute_serial
      with_each_environment do |_, i|
        if debug
          execute_in_foreground(i)
        else
          execute_in_background(i)
        end
      end
    end

    def execute_parallel
      threads = []
      with_each_environment do |_, i|
        threads << Thread.new { execute_in_background(i) }
      end
      threads.each {|t| t.join}
    end

    def with_each_environment
      environments.each_with_index do |gemfile_text, i|
        next unless should_run_environment?(i)
        yield gemfile_text, i
      end
    end

    def should_run_environment?(index)
      return true unless filter_env
      return filter_env == index
    end

    def with_unbundled_env
      with_potentially_mismatched_bundler do
        if defined?(Bundler)
          # clear $BUNDLE_GEMFILE and $RUBYOPT so that the ruby subprocess can run
          # in the context of another bundle.

          Bundler.with_unbundled_env { yield }
        else
          yield
        end
      end
    end

    def execute_in_foreground(env)
      with_unbundled_env do
        puts yellow("Running #{suite.inspect} for Envfile entry #{env}\n")
        system(child_command_line(env))
        check_for_failure(env)
      end
    end

    def execute_in_background(env)
      with_unbundled_env do
        OutputCollector.write(suite, env, yellow("Running #{suite.inspect} for Envfile entry #{env}\n"))

        IO.popen(child_command_line(env)) do |io|
          until io.eof do
            chars = io.read
            OutputCollector.write(suite, env, chars)
          end
          OutputCollector.suite_report(suite, env)
        end

        check_for_failure(env)
      end
    end

    def child_command_line(env)
      "#{__FILE__} #{directory} #{env} '#{Suite.encode_options(opts)}'"
    end

    def check_for_failure(env)
      if $? != 0
        OutputCollector.write(suite, env, red("#{suite.inspect} for Envfile entry #{env} failed!"))
        OutputCollector.failed(suite, env)
      end
      Multiverse::Runner.notice_exit_status $?
    end

    def trigger_test_run
      # We drive everything manually ourselves through MiniTest.
      #
      # Autorun behaves differently across the different Ruby version we have
      # to support, so this is simplest for making our test running consistent
      options = []
      options << "-v" if verbose?
      options << "--seed=#{seed}" unless seed == ""
      options << "--name=/#{names.map {|n| n + ".*"}.join("|")}/" unless names == []

      original_options = options.dup

      # MiniTest 5.0 moved things around, so choose which way to run it
      if ::MiniTest.respond_to?(:run)
        test_run = ::MiniTest.run(options)
      else
        test_run = ::MiniTest::Unit.new.run(options)
      end

      load @after_file if @after_file

      if test_run
        exit(test_run)
      else
        puts "No tests found with those options."
        puts "options: #{original_options}"
        exit(1)
      end
    end

    def configure_before_bundling
      disable_harvest_thread
      configure_fake_collector
    end

    def configure_child_environment
      require_minitest
      patch_minitest_base_for_old_versions
      prevent_minitest_auto_run
      require_mocha
      require_helpers
    end

    def patch_minitest_base_for_old_versions
      unless defined?(Minitest::Test)
        ::Minitest.class_eval do
          const_set(:Test, ::MiniTest::Unit::TestCase)
        end
      end
    end

    # Rails and minitest_tu_shim both want to do MiniTest::Unit.autorun for us
    # We can't sidestep, so just gut the method to avoid doubled test runs
    def prevent_minitest_auto_run
      # MiniTest 4.x
      ::MiniTest::Unit.class_eval do
        def self.autorun
          # NO-OP
        end
      end

      # MiniTest 5.x
      ::MiniTest.class_eval do
        def self.autorun
          # NO-OP
        end
      end
    end

    def require_mocha
      require 'mocha/setup'
    end

    def disable_harvest_thread
      # We don't want to have additional harvest threads running in our multiverse
      # tests. The tests explicitly manage their lifecycle--resetting and harvesting
      # to check results against the FakeCollector--so the harvest thread is actually
      # destabilizing if it's running. Also, multiple restarts result in lots of
      # threads running in some test suites.

      ENV["NEWRELIC_DISABLE_HARVEST_THREAD"] = "true"
    end

    def configure_fake_collector
      ENV["NEWRELIC_OMIT_FAKE_COLLECTOR"] = "true" if environments.omit_collector
    end

    def require_helpers
      # If used from a 3rd-party, these paths likely need to be added
      $: << File.expand_path('../../../..', __FILE__)
      $: << File.expand_path('../../../../new_relic', __FILE__)
      require 'multiverse_helpers'
    end

    def execute_ruby_files
      Dir.chdir directory
      ordered_ruby_files(directory).each do |file|
        puts yellow("Executing #{file.inspect}") if verbose?
        next if exclude?(file)
        require "./" + File.basename(file, ".rb")
      end
    end

    def ordered_ruby_files(directory)
      files = Dir[File.join(directory, '*.rb')]

      @before_file = files.find { |file| File.basename(file) == "before_suite.rb" }
      @after_file  = files.find { |file| File.basename(file) == "after_suite.rb" }

      files.delete(@before_file)
      files.delete(@after_file)

      # Important that we filter after removing before/after so they don't get
      # tromped for not matching our pattern!
      files.select! {|file| file.include?(filter_file) } if filter_file

      # Just put before_suite.rb at the head of the list.
      # Will explicitly load after_suite.rb after the test run
      files.insert(0, @before_file) if @before_file

      files
    end

    def verbose?
      ENV['VERBOSE'] == "1" || ENV['VERBOSE'] == "true"
    end

    # Sidekiq v4.2.0 and later will bail out at startup if we try to
    # run (with the --require option) a file that we've already loaded
    # ourselves; see https://github.com/mperham/sidekiq/pull/3114
    #
    # To work around this behavior, we'll configure our test framework
    # not to load our TestWorker class; Sidekiq will load it for us.
    #
    # If we ever need to exclude other files from the test suite for
    # similar reasons, we should change this hardcoded file name into
    # a configuration option.
    #
    EXCLUDED_FILES = %w(test_worker.rb)

    def exclude?(file)
      EXCLUDED_FILES.include?(File.basename(file))
    end
  end
end

# Execute the suite.  We need this if we want to execute a suite by spawning a
# new process instead of forking.
if $0 == __FILE__ && $already_running.nil?
  # Suite might get re-required, but don't execute again
  $already_running = true

  # Redirect stderr to stdout so that we can capture both in the popen that
  # feeds into the OutputCollector above.
  $stderr.reopen($stdout)

  # Ugly, but seralized args passed along to #popen when kicking child off
  dir, env_index, encoded_opts, _ = *ARGV
  opts = Multiverse::Suite.decode_options(encoded_opts)
  suite = Multiverse::Suite.new(dir, opts)
  suite.execute_child_environment(env_index.to_i)
end
