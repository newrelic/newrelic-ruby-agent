# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class StatsHashPerfTest < Performance::TestCase
  def setup
    @hash = NewRelic::Agent::StatsHash.new
  end

  def test_record(timer)
    iterations.times do
      hash = NewRelic::Agent::StatsHash.new
      timer.measure do
        100.times do |i|
          hash.record("foo#{i}", 1)
        end
      end
    end
  end

  def test_merge(timer)
    iterations.times do
      incoming = {}
      100.times do |i|
        incoming["foo#{i}"] = NewRelic::Agent::Stats.new
      end

      hash = NewRelic::Agent::StatsHash.new
      timer.measure do
        hash.merge!(incoming)
      end
    end
  end
end
