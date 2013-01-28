# This module is responsible for intercepting output made through various stdlib
# calls (i.e. puts, print, etc.) and printing summary information (e.g. a list
# of failing tests) at the end of the process.
#
module Multiverse
  module OutputCollector
    include Color
    extend Color
    def self.buffers
      @buffer ||= []
    end

    def self.failing_output
      @failing ||= []
    end

    def self.report
      puts
      puts
      if failing_output.empty?
        puts green("There were no test failures")
      else
        puts red("There were failures in #{failing_output.size} test suites")
        puts "Here is their output"
        puts *failing_output
      end
    end
  end
end
