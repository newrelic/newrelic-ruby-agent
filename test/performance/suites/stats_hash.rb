# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class StatsHashPerfTest < Performance::TestCase
  def setup
    @hash = NewRelic::Agent::StatsHash.new
    @specs = (1..100).map { |i| NewRelic::MetricSpec.new("foo#{i}") }
  end

  def test_record
    measure do
      hash = NewRelic::Agent::StatsHash.new
      @specs.each do |spec|
        hash.record(spec, 1)
      end
    end
  end

  def test_merge
    measure do
      incoming = NewRelic::Agent::StatsHash.new
      @specs.each do |i|
        incoming.record(NewRelic::MetricSpec.new("foo#{i}"), 1)
      end

      hash = NewRelic::Agent::StatsHash.new
      hash.merge!(incoming)
    end
  end
end
