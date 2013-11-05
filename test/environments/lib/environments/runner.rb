# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'multiverse', 'lib', 'multiverse', 'color'))

module Environments
  class Runner
    include Multiverse::Color

    BLACKLIST = {
      "1.8.6"       => ["rails30", "rails31", "rails32", "rails40", "norails"],
      "1.8.7"       => ["rails40"],
      "ree"         => ["rails40"],
      "1.9.1"       => ["rails21", "rails22", "rails30", "rails31", "rails32", "rails40", "norails"],
      "1.9.2"       => ["rails21", "rails22", "rails40"],
      "1.9.3"       => ["rails21", "rails22"],
      "2.0.0"       => ["rails21", "rails22", "rails23"],
      "jruby-1.6"   => ["rails40"],
      "jruby-1.7"   => ["rails21", "rails22", "rails23"],
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
          bundle(dir)
          create_database(dir)
          status = run(dir)
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

      blacklist = BLACKLIST[version] || []
      blacklist.each do |blacklisted|
        dirs.delete_if {|d| File.basename(d) == blacklisted }
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
        bundling = `cd #{dir} && bundle install`
      end

      bundling = red(bundling) unless $?.success?
      puts bundling
    end

    # Would be nice to get our unit tests decoupled from the actual DB, but
    # until then this is necessary
    def create_database(dir)
      return if File.basename(dir) == "norails"

      puts "Making sure the database is there for '#{File.basename(dir)}'..."
      result = `cd #{dir} && RAILS_ENV=test bundle exec rake --trace db:create`
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
