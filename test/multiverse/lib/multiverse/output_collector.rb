# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module is responsible for intercepting output made through various stdlib
# calls (i.e. puts, print, etc.) and printing summary information (e.g. a list
# of failing tests) at the end of the process.

require 'thread'

module Multiverse
  module OutputCollector
    include Color
    extend Color

    @output_lock = Mutex.new
    @buffer_lock = Mutex.new

    def self.failing_output
      @failing_output ||= []
    end

    def self.buffer(suite, env)
      key = [suite, env]
      @buffer_lock.synchronize do
        @buffers ||= {}
        @buffers[key] ||= ""
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
      output("", "")
      if failing_output.empty?
        output(green("There were no test failures"))
      else
        to_output = failing_output_header + failing_output + failing_output_footer
        output(*to_output)
      end
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

    # Because the various environments potentially run in separate threads to
    # start their processes, make sure we don't blatantly interleave output.
    def self.output(*args)
      @output_lock.synchronize do
        puts(*args)
      end
    end
  end
end
