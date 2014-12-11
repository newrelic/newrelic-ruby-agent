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

    def format_duration(d)
      if d < 0.001
        ds = d * 1000 * 1000
        unit = "us"
      elsif d < 1.0
        ds = d * 1000
        unit = "ms"
      else
        ds = d
        unit = "s"
      end

      sprintf("%.2f %s", ds, unit)
    end

    def format_measurements(result)
      key_width        = result.measurements.keys.map(&:size).max
      formatted_values = result.measurements.values.map { |v| sprintf("%g", v) }
      value_width      = formatted_values.map(&:size).max

      rows = result.measurements.map do |key, value|
        per_iteration = value / result.iterations.to_f
        "  %#{key_width}s: %#{value_width}g (%.2f / iter)" % [key, value, per_iteration]
      end

      rows.join("\n") + "\n"
    end

    def report_successful_results(results)
      return if successes.empty?

      puts ''
      results.each do |result|
        puts "#{result.identifier}: %.3f ips (#{format_duration(result.time_per_iteration)} / iteration)" % [result.ips]
        puts "  #{result.iterations} iterations"
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
