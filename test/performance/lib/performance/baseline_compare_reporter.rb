# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class BaselineCompareReporter
    include Reporting

    def initialize(results, elapsed, options = {})
      @results = results
      @elapsed = elapsed
      @options = options
    end

    def report
      report_summary

      begin
        baseline = Baseline.load!
      rescue => e
        puts "Failed to load baseline results: #{e}\n#{e.backtrace.join("\n\t")}"
        return
      end

      report_successful_results(baseline, successes) unless successes.empty?
      report_failed_results
    end

    def report_successful_results(baseline, results)
      baseline_identifiers = baseline.map(&:identifier)
      new_identifiers = results.map(&:identifier)
      missing_from_baseline = new_identifiers - baseline_identifiers
      missing_from_new = baseline_identifiers - new_identifiers
      common_identifiers = new_identifiers & baseline_identifiers

      if !missing_from_baseline.empty?
        puts "The following tests were not found in the baseline results:\n"
        missing_from_baseline.each do |identifier|
          puts "  #{identifier}"
        end
        puts ''
      end

      if !missing_from_baseline.empty?
        puts "The following tests were not found in the new results:\n"
        missing_from_new.each do |identifier|
          puts "  #{identifier}"
        end
        puts ''
      end

      rows = []

      common_identifiers.each do |identifier|
        old_result = baseline.find { |r| r.identifier == identifier }
        new_result = results.find { |r| r.identifier == identifier }

        delta = new_result.time_per_iteration - old_result.time_per_iteration
        percent_delta = delta / old_result.time_per_iteration * 100.0

        allocations_before = old_result.measurements[:allocations]
        allocations_after = new_result.measurements[:allocations]
        allocations_delta_percent = 0
        if allocations_before && allocations_after
          # normalize allocation counts to be per-iteration
          allocations_before /= old_result.iterations
          allocations_after /= new_result.iterations

          allocations_delta = allocations_after - allocations_before
          allocations_delta_percent = allocations_delta.to_f / allocations_before * 100
        end

        retained_before = old_result.measurements[:retained]
        retained_after = new_result.measurements[:retained]
        retained_delta = 0
        retained_percent = 0
        if retained_before && retained_after
          # normalize allocation counts to be per-iteration
          retained_before /= old_result.iterations
          retained_after /= new_result.iterations

          retained_delta = retained_after - retained_before
          retained_percent = retained_delta.to_f / retained_before * 100
        end
        retained_percent = 0.0 if (retained_percent.to_f).nan?

        rows << [
          identifier,
          old_result.time_per_iteration,
          new_result.time_per_iteration,
          percent_delta,
          allocations_before,
          allocations_after,
          allocations_delta_percent,
          retained_delta,
          retained_percent
        ]
      end

      format_percent_delta = proc { |v|
        prefix = v > 0 ? '+' : ''
        sprintf("#{prefix}%.1f%%", v)
      }

      table = Table.new(rows, @options) do
        column(:name)
        column(:before, &(FormattingHelpers.method(:format_duration)))
        column(:after, &(FormattingHelpers.method(:format_duration)))
        column(:delta, &format_percent_delta)
        column(:allocs_before)
        column(:allocs_after)
        column(:allocs_delta, &format_percent_delta)
        column(:retained)
        column(:retained_delta, &format_percent_delta)
      end

      puts table.render
    end
  end
end
