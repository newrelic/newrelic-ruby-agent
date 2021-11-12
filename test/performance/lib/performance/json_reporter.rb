# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module Performance
  class JSONReporter
    def initialize(results, _elapsed, _options = {})
      @results = results
    end

    def report
      puts JSON.dump(@results.map { |result| result.to_h })
    end
  end
end
