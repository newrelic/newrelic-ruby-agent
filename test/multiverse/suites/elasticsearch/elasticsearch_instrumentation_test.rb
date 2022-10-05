# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ElasticsearchInstrumentationTest < Minitest::Test
  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def port
    if defined?(::Elasticsearch)
      puts "elastic 7"
      9200 # 9200 for elasticsearch 7
    else
      puts "elastic 8"
      9250 # 9250 for elasticsearch 8
    end
  end

  def test_test
    # only works on 7 rn for some reason
    client = Elasticsearch::Client.new(port: port)
    puts client.search(q: 'test')
  end
end
