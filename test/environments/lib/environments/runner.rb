# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'multiverse', 'lib', 'multiverse', 'color'))

module Environments
  class Runner
    include Multiverse::Color

    attr_reader :envs

    def initialize(envs)
      @envs = envs
    end

    def env_root
      File.join(File.dirname(__FILE__), "..", "..")
    end

    def run_and_report
      overall_status = 0

      puts yellow("Tests to run:\n\t#{tests_to_run.map{|s|s.gsub(env_root + "/", "")}.join("\n\t")}\n")
      tests_to_run.each do |dir|
        Bundler.with_clean_env do
          puts yellow("Running tests for #{dir}")
          bundle(dir)
          status = run(dir)
          overall_status = status.exitstatus if overall_status == 0 && !(status.success?)
        end
      end

      exit(overall_status)
    end

    def tests_to_run
      original_dirs = Dir["#{env_root}/*"].reject { |d| File.basename(d) == "lib"}

      dirs = []
      envs.each do |dir|
        dirs.concat(original_dirs.select { |d| File.basename(d).start_with?(dir) })
      end
      dirs
    end

    def bundle(dir)
      puts "Bundling..."
      bundling = `cd #{dir} && bundle install`
      puts red(bundling) unless $?.success?
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
