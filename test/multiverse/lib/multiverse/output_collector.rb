# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This module is responsible for intercepting output made through various stdlib
# calls (i.e. puts, print, etc.) and printing summary information (e.g. a list
# of failing tests) at the end of the process.

require 'thread'
require_relative 'time_report_output'

module Multiverse
  module OutputCollector
    include Color
    extend Color
    extend TimeReportOutput

    @output_lock = Mutex.new
    @buffer_lock = Mutex.new

    def self.failing_output
      @failing_output ||= []
    end

    def self.buffer(suite, env)
      key = [suite, env]
      @buffer_lock.synchronize do
        @buffers ||= {}
        @buffers[key] ||= +''
        @buffers[key]
      end
    end

    def self.failed(suite, env)
      @failing_suites ||= []
      @failing_suites << [suite, env]

      @failing_output ||= []
      @failing_output << buffer(suite, env) + "\n"
    end

    def self.write(suite, env, msg)
      buffer(suite, env) << msg
    end

    def self.suite_report(suite, env)
      output(buffer(suite, env))
    end

    def self.overall_report
      output('', '')
      if failing_output.empty?
        output(green("There were no test failures"))
      else
        to_output = failing_output_header + failing_output + failing_output_footer
        output(*to_output)
        save_output_to_error_file(failing_output)
      end
      sort_and_print_test_times
    end

    def self.failing_output_header
      [red("*" * 80),
        red("Repeating failed test output"),
        red("*" * 80),
        ""]
    end

    def self.failing_output_footer
      ["",
        red("*" * 80),
        red("There were failures in #{failing_output.size} test suites"),
        "",
        @failing_suites.map { |suite, env| red("#{suite} failed in env #{env}") },
        red("*" * 80)]
    end

    # Saves the failing out put to the working directory of the container
    # where it is later read and output as annotations of the github workflow
    def self.save_output_to_error_file(lines)
      @output_lock.synchronize do
        filepath = ENV["GITHUB_WORKSPACE"] || File.expand_path(File.dirname(__FILE__))
        output_file = File.join(filepath, "errors.txt")

        existing_lines = []
        if File.exist?(output_file)
          existing_lines += File.read(output_file).split("\n")
        end

        lines = lines.split("\n") if lines.is_a?(String)
        File.open(output_file, 'w') do |f|
          f.puts existing_lines
          f.puts "*" * 80
          f.puts lines
        end
      end
    end

    # Because the various environments potentially run in separate threads to
    # start their processes, make sure we don't blatantly interleave output.
    def self.output(*args)
      @output_lock.synchronize do
        puts(*args)
      end
    end
  end
end
