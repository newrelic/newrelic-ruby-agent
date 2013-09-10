# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class ConsoleReporter
    def initialize(results, elapsed, options={})
      @results = results
      @elapsed = elapsed
      @options = options
    end

    def report
      failures = @results.select { |result| result.failure? }
      successes = @results - failures
      puts "#{@results.size} tests, #{failures.size} failures, #{@elapsed} s total"
      report_successful_results(successes) if successes.any?
      report_failed_results(failures) if failures.any?
    end

    def report_successful_results(results)
      puts ''
      results.each do |result|
        puts "#{result.identifier}: #{result.elapsed} s"
        unless @options[:brief]
          result.measurements.each do |key, value|
            puts "  %s: %g" % [key, value]
          end
        end
        unless result.artifacts.empty?
          puts "  artifacts:"
          result.artifacts.each do |artifact|
            puts "    #{artifact}"
          end
        end
        puts '' if !@options[:brief] || !result.artifacts.empty?
      end
    end

    def report_failed_results(results)
      puts ''
      results.each do |failure|
        puts "FAILED: #{failure.identifier}"
        e = failure.exception
        puts "#{e['class']}: #{e['message']}"
        puts failure.exception['backtrace'].map { |l| "    #{l}" }.join("\n")
      end
      puts ''
    end
  end
end
