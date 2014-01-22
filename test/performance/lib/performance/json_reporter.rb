# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class JSONReporter
    def initialize(results, elapsed, options={})
      @results = results
    end

    def report
      puts JSON.dump(@results.map { |result| result.to_h })
    end
  end
end
