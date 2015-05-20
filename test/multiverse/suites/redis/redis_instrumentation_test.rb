# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'redis'
require 'newrelic_rpm'

class NewRelic::Agent::Instrumentation::RedisInstrumentationTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent

  def after_setup
    super
    @redis = Redis.new
  end

  def after_teardown
    @redis.flushall
  end

  def test_records_metrics_for_set
    @redis.set 'shivan', 'dragon'

    expected = {
      "Datastore/operation/Redis/set" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allOther"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_get
    @redis.get 'mox'

    expected = {
      "Datastore/operation/Redis/get" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allOther"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end
end
