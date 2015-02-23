# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'pathname'

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

    def format_measurements(result)
      measurements = result.measurements.merge(:iterations => result.iterations)

      key_width        = measurements.keys.map(&:size).max
      formatted_values = measurements.values.map { |v| sprintf("%g", v) }
      value_width      = formatted_values.map(&:size).max

      rows = measurements.map do |key, value|
        if key == :iterations
          "  %#{key_width}s: %#{value_width}g" % [key, value]
        else
          per_iteration = value / result.iterations.to_f
          "  %#{key_width}s: %#{value_width}g (%.2f / iter)" % [key, value, per_iteration]
        end
      end

      rows.join("\n") + "\n"
    end

    def report_successful_results(results)
      return if successes.empty?

      puts ''
      results.each do |result|
        formatted_duration = FormattingHelpers.format_duration(result.time_per_iteration)
        puts "#{result.identifier}: %.3f ips (#{formatted_duration} / iteration)" % [result.ips]
        unless @options[:brief]
          puts format_measurements(result)
        end
        unless result.artifacts.empty?
          puts "  artifacts:"
          result.artifacts.each do |artifact|
            puts "    #{make_relative(artifact)}"
          end
        end
        puts '' if !@options[:brief] || !result.artifacts.empty?
      end
    end

    def make_relative(path)
      "./#{Pathname.new(path).relative_path_from(Pathname.getwd)}"
    end
  end
end
