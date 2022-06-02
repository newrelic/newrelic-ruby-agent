# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../multiverse/lib/multiverse/bundler_patch'
require_relative '../../../multiverse/lib/multiverse/color'
require_relative '../../../multiverse/lib/multiverse/shell_utils'

module Environments
  class Runner
    include Multiverse::Color

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

      puts yellow("Tests to run:\n\t#{tests_to_run.map { |s| s.gsub(env_root + "/", "") }.join("\n\t")}")
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
      original_dirs = Dir["#{env_root}/*"].reject { |d| File.basename(d) == "lib" }

      return original_dirs if envs.empty?
      dirs = []
      envs.each do |dir|
        dirs.concat(original_dirs.select { |d| File.basename(d).index(dir) == 0 })
      end
      dirs
    end

    # Ensures we bundle will recognize an explicit version number on command line
    def safe_explicit version
      return version if version.to_s == ""
      test_version = `bundle #{version} --version` =~ /Could not find command/
      test_version ? "" : version
    end

    def explicit_bundler_version dir
      return if RUBY_VERSION.to_f <= 2.3
      fn = File.join(dir, ".bundler-version")
      version = File.exist?(fn) ? File.read(fn).chomp!.strip : nil
      safe_explicit(version.to_s == "" ? nil : "_#{version}_")
    end

    def bundle_config dir, bundle_cmd
      `cd #{dir} && #{bundle_cmd} config build.nokogiri --use-system-libraries`
    end

    def bundle(dir)
      puts "Bundling in #{dir}..."
      bundler_version = explicit_bundler_version(dir)
      bundle_cmd = "bundle #{explicit_bundler_version(dir)}".strip
      bundle_config dir, bundle_cmd

      command = "cd #{dir} && #{bundle_cmd} install"
      result = Multiverse::ShellUtils.try_command_n_times(command, 3)

      result = red(result) unless $?.success?
      puts result
      $?
    end

    def run(dir)
      puts "Starting tests for dir '#{dir}'..."
      cmd = "cd #{dir} && bundle exec rake"
      cmd << " file=#{ENV['file']}" if ENV["file"]

      IO.popen(cmd) do |io|
        until io.eof
          print io.read(1)
        end
      end
      $?
    end
  end
end
