# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'multiverse', 'lib', 'multiverse', 'color'))

module Environments
  class Runner
    include Multiverse::Color

    BLACKLIST = {
      "2.2.1"       => ["rails50"],
      "2.2.0"       => ["rails50"],
      "2.1"         => ["rails50"],
      "2.0"         => ["rails50"],
      "2"           => ["rails21", "rails22", "rails23"],
      "1.9"         => ["rails21", "rails22", "rails50"],
      "1.9.2"       => ["rails40", "rails41", "rails42", "rails50"],
      "1.8.7"       => ["rails40", "rails41", "rails42", "rails50"],
      "ree"         => ["rails40", "rails41", "rails42", "rails50"],
      "jruby-1.6"   => ["rails40", "rails41", "rails42", "rails50"],
      "jruby-1.7"   => ["rails21", "rails22", "rails23", "rails50"],
      "jruby-9.0"   => ["rails21", "rails22", "rails23", "rails30", "rails31", "rails32"],
      "rbx-2.0"     => ["rails21", "rails22", "rails23", "rails30", "rails31", "rails32"],
    }

    attr_reader :envs

    def initialize(envs)
      @envs = envs
    end

    def env_root
      File.join(File.dirname(__FILE__), "..", "..")
    end

    def run_and_report
      overall_status = 0
      failures = []

      puts yellow("Tests to run:\n\t#{tests_to_run.map{|s|s.gsub(env_root + "/", "")}.join("\n\t")}")
      tests_to_run.each do |dir|
        Bundler.with_clean_env do
          dir = File.expand_path(dir)
          puts "", yellow("Running tests for #{dir}")
          status = bundle(dir)
          status = run(dir) if status.success?

          if !status.success?
            overall_status += 1
            failures << dir
          end
        end
      end

      if overall_status == 0
        puts green("All good to go. Yippy!")
      else
        puts red("Oh no, #{overall_status} environments failed!"), "", red(failures.join("\n"))
      end

      exit(overall_status)
    end

    def tests_to_run
      dirs = potential_directories

      version = RUBY_VERSION
      version = "ree" if defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /Ruby Enterprise Edition/
      version = "jruby-#{JRUBY_VERSION[0..2]}" if defined?(JRUBY_VERSION)
      version = "rbx-2.0" if defined?(RUBY_ENGINE) && RUBY_ENGINE == "rbx"

      BLACKLIST.each do |check_version, blacklisted|
        if version.start_with?(check_version)
          dirs.reject! {|d| blacklisted.include?(File.basename(d)) }
        end
      end

      dirs
    end

    def potential_directories
      original_dirs = Dir["#{env_root}/*"].reject { |d| File.basename(d) == "lib"}

      return original_dirs if envs.empty?
      dirs = []
      envs.each do |dir|
        dirs.concat(original_dirs.select { |d| File.basename(d).index(dir) == 0 })
      end
      dirs
    end

    def bundle(dir)
      puts "Bundling in #{dir}..."
      bundling = `cd #{dir} && bundle install --local`
      unless $?.success?
        puts "Failed local bundle, trying again with full bundle..."
        bundling = `cd #{dir} && bundle install --retry 3`
      end

      bundling = red(bundling) unless $?.success?
      puts bundling
      $?
    end

    def run(dir)
      puts "Starting tests..."
      IO.popen("cd #{dir} && bundle exec rake") do |io|
        until io.eof do
          print io.read(1)
        end
      end
      $?
    end
  end
end
