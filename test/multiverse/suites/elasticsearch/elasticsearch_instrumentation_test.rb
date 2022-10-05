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
      9200
    else
      9250
    end
  end

  def client
    if defined?(::Elasticsearch)
      ::Elasticsearch::Transport::Client
    else
      ::Elastic::Transport::Client
    end
  end

  def test_test
    client = Elasticsearch::Client.new(port: port)
    puts client.search(q: 'test')
  end
end
