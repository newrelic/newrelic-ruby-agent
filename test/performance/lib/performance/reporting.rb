# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  module Reporting
    def failures
      @failures ||= @results.select(&:failure?)
    end

    def successes
      @successes ||= @results.reject(&:failure?)
    end

    def report_summary
      puts "#{@results.size} tests, #{failures.size} failures, #{@elapsed} s total"
    end

    def report_failed_results
      return if failures.empty?

      puts ''
      failures.each do |failure|
        puts "FAILED: #{failure.identifier}"
        e = failure.exception
        if e
          puts "#{e['class']}: #{e['message']}"
          puts failure.exception['backtrace'].map { |l| "    #{l}" }.join("\n")
        else
          puts "<No exception recorded>"
        end
      end
      puts ''
    end
  end
end
