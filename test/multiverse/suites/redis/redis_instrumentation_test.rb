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
    @redis.set 'time', 'walk'

    expected = {
      "Datastore/operation/Redis/set" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allOther"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_get_in_web_transaction
    in_web_transaction do
      @redis.set 'prodigal', 'sorcerer'
    end

    expected = {
      "Datastore/operation/Redis/set" => { :call_count => 1 },
      "Datastore/Redis/allWeb" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allWeb"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_get
    @redis.get 'mox sapphire'

    expected = {
      "Datastore/operation/Redis/get" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allOther"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_set_in_web_transaction
    in_web_transaction do
      @redis.get 'timetwister'
    end

    expected = {
      "Datastore/operation/Redis/get" => { :call_count => 1 },
      "Datastore/Redis/allWeb" => { :call_count => 1 },
      "Datastore/Redis/all"=> { :call_count => 1 },
      "Datastore/allWeb"=> { :call_count => 1 },
      "Datastore/all"=> { :call_count => 1 }
    }
    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_pipelined_commands
    @redis.pipelined do
      @redis.get 'great log'
      @redis.get 'late log'
    end

    expected = {
      "Datastore/operation/Redis/pipeline" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all" => { :call_count => 1 },
      "Datastore/allOther" => { :call_count => 1 },
      "Datastore/all" => { :call_count => 1 }
    }
    assert_metrics_recorded_exclusive(expected, :ignore_filter => /Supportability/)
  end
end
