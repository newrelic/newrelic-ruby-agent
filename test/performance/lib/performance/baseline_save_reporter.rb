# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class BaselineSaveReporter
    include Reporting

    def initialize(results, elapsed, options = {})
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
