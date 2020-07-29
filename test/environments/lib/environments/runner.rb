# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path '../../../../multiverse/lib/multiverse/bundler_patch', __FILE__
require File.expand_path '../../../../multiverse/lib/multiverse/color', __FILE__
require File.expand_path '../../../../multiverse/lib/multiverse/shell_utils', __FILE__

module Environments
  class Runner
    include Multiverse::Color

    DENYLIST = {
      "2.4.2"       => ["rails60"],
      "2.3.5"       => ["rails60"],
      "2.2.1"       => ["rails50", "rails60"],
      "2.2"         => ["rails50", "rails60"],
      "2.1"         => ["rails50", "rails60"],
      "2.0"         => ["rails50", "rails60"],
      "jruby-9.2.6.0" => ["rails60"],
      "jruby-9.0"   => ["rails30", "rails31", "rails32"]
    }

    attr_reader :envs

    def initialize(envs)
      @envs = envs
    end

    def env_root
      File.expand_path '../../..', __FILE__
    end

    def run_and_report
      overall_status = 0
      failures = []

      puts yellow("Tests to run:\n\t#{tests_to_run.map{|s|s.gsub(env_root + "/", "")}.join("\n\t")}")
      env_file = ENV["file"]
      tests_to_run.each do |dir|
        Bundler.with_unbundled_env do
          ENV["file"] = env_file if env_file
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
      version = "jruby-#{JRUBY_VERSION[0..2]}" if defined?(JRUBY_VERSION)

      DENYLIST.each do |check_version, denylisted|
        if version.start_with?(check_version)
          dirs.reject! {|d| denylisted.include?(File.basename(d)) }
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

    def explicit_bundler_version dir
      return if RUBY_VERSION.to_f < 2.3
      fn = File.join(dir, ".bundler-version")
      version = File.exist?(fn) ? File.read(fn).chomp!.strip : nil
      version.to_s == "" ? nil : "_#{version}_"
    end

    def bundle(dir)
      puts "Bundling in #{dir}..."
      bundler_version = explicit_bundler_version(dir)
      bundle_cmd = "bundle #{explicit_bundler_version(dir)}".strip
      result = `cd #{dir} && #{bundle_cmd} install --local`
      unless $?.success?
        puts "Failed local bundle, trying again with full bundle..."
        command = "cd #{dir} && #{bundle_cmd} install --retry 3"
        result = Multiverse::ShellUtils.try_command_n_times(command, 3)
      end

      result = red(result) unless $?.success?
      puts result
      $?
    end

    def run(dir)
      puts "Starting tests..."
      cmd = "cd #{dir} && bundle exec rake"
      cmd << " file=#{ENV['file']}" if ENV["file"]
      IO.popen(cmd) do |io|
        until io.eof do
          print io.read(1)
        end
      end
      $?
    end
  end
end
