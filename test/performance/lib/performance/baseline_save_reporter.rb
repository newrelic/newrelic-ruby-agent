# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class BaselineSaveReporter
    include Reporting

    def initialize(results, elapsed, options={})
      @results = results
      @elapsed = elapsed
      @options = options
    end

    def report
      report_summary

      Baseline.save!(successes)
      puts "Saved #{successes.size} results as baseline."

      report_failed_results
    end
  end
end
