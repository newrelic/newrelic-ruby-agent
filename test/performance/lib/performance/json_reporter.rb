# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class JSONReporter
    def initialize(results, elapsed, options = {})
      @results = results
    end

    def report
      puts JSON.dump(@results.map { |result| result.to_h })
    end
  end
end
