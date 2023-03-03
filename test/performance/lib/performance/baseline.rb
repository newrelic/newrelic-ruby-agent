# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class Baseline
    PERSIST_PATH = File.expand_path(ENV.fetch('NEWRELIC_RPM_BASELINE_FILE', '~/.newrelic_rpm_baseline'))

    attr_reader :results

    def self.load!
      self.new.load!
    end

    def self.save!(results)
      baseline = self.new
      results.each { |r| baseline.results << r }
      baseline.save!
    end

    def initialize
      @results = []
    end

    def load!
      result_hashes = JSON.parse(File.read(PERSIST_PATH))
      @results = result_hashes.map { |h| Result.from_hash(h) }
    end

    def save!
      File.write(PERSIST_PATH, JSON.dump(@results.map(&:to_h)))
    end
  end
end
