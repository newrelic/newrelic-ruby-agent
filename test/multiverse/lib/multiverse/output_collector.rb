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
      @failing ||= []
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
      @failing ||= []
      @failing << buffer(suite, env) + "\n"
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
        output(
          red("There were failures in #{failing_output.size} test suites"),
          "Here is their output",
          *failing_output)
      end
    end

    # Because the various environments potentially run in separate threads to
    # start their processes, make sure we don't blatantly interleave output.
    def self.output(*args)
      @output_lock.synchronize do
        puts *args
      end
    end
  end
end
