# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class BaselineCompareReporter
    include Reporting

    def initialize(results, elapsed, options={})
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
      baseline_identifiers  = baseline.map(&:identifier)
      new_identifiers       = results.map(&:identifier)
      missing_from_baseline = new_identifiers - baseline_identifiers
      missing_from_new      = baseline_identifiers - new_identifiers
      common_identifiers    = new_identifiers & baseline_identifiers

      if !missing_from_baseline.empty?
        puts "The following tests were not found in the baseline results:\n"
        missing_from_baseline.each do |identifier|
          puts "  #{identifier}"
        end
        puts ""
      end

      if !missing_from_baseline.empty?
        puts "The following tests were not found in the new results:\n"
        missing_from_new.each do |identifier|
          puts "  #{identifier}"
        end
        puts ""
      end

      rows = []

      common_identifiers.each do |identifier|
        old_result = baseline.find { |r| r.identifier == identifier}
        new_result = results.find  { |r| r.identifier == identifier }

        delta = new_result.elapsed - old_result.elapsed
        percent_delta = delta / old_result.elapsed * 100.0

        allocations_before = old_result.measurements[:allocations]
        allocations_after  = new_result.measurements[:allocations]
        if allocations_before && allocations_after
          allocations_delta  = allocations_after - allocations_before
          allocations_delta_percent = allocations_delta.to_f / allocations_before * 100
        else
          allocations_delta_percent = 0
        end

        rows << [
          identifier,
          old_result.elapsed,
          new_result.elapsed,
          percent_delta,
          allocations_before,
          allocations_after,
          allocations_delta_percent
        ]
      end

      format_percent_delta = Proc.new { |v|
        prefix = v > 0 ? "+" : ""
        sprintf("#{prefix}%.1f%%", v)
      } 

      table = Table.new(rows) do
        column :name
        column :before,        "%.2f s"
        column :after,         "%.2f s"
        column :delta,         &format_percent_delta
        column :allocs_before
        column :allocs_after
        column :allocs_delta,  &format_percent_delta
      end

      puts table.render
    end
  end
end
