# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class ConsoleReporter
    include Reporting

    def initialize(results, elapsed, options={})
      @results = results
      @elapsed = elapsed
      @options = options
    end

    def report
      report_summary
      report_successful_results(successes) unless successes.empty?
      report_failed_results
    end

    def report_successful_results(results)
      return if successes.empty?

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
  end
end
