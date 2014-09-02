# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Baseline
    PERSIST_PATH = File.expand_path("~/.newrelic_rpm_baseline")

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
      File.open(PERSIST_PATH, "w") do |f|
        f.write(JSON.dump(@results.map(&:to_h)))
      end
    end
  end
end