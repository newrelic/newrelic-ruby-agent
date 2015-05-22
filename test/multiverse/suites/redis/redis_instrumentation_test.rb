# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'redis'
require 'newrelic_rpm'

if NewRelic::Agent::Datastores::Redis.is_supported_version?
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

  def test_records_tt_node_for_get
    in_transaction do
      @redis.get 'mox sapphire'
    end

    tt = last_transaction_trace
    get_node = tt.root_node.called_nodes[0].called_nodes[0]
    assert_equal('Datastore/operation/Redis/get', get_node.metric_name)
  end

  def test_records_statement_on_tt_node_for_get
    in_transaction do
      @redis.get 'mox sapphire'
    end

    tt = last_transaction_trace
    get_node = tt.root_node.called_nodes[0].called_nodes[0]
    assert_equal('get ?', get_node[:statement])
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

  def test_records_commands_in_tt_node_for_pipelined_commands
    in_transaction do
      @redis.pipelined do
        @redis.set 'late log', 'goof'
        @redis.get 'great log'
      end
    end

    tt = last_transaction_trace
    pipeline_node = tt.root_node.called_nodes[0].called_nodes[0]

    assert_equal("set ?\nget ?", pipeline_node[:statement])
  end

  def test_records_metrics_for_multi_blocks
    @redis.multi do
      @redis.get 'darkpact'
      @redis.get 'chaos orb'
    end

    expected = {
      "Datastore/operation/Redis/multi" => { :call_count => 1 },
      "Datastore/Redis/allOther" => { :call_count => 1 },
      "Datastore/Redis/all" => { :call_count => 1 },
      "Datastore/allOther" => { :call_count => 1 },
      "Datastore/all" => { :call_count => 1 }
    }
    assert_metrics_recorded_exclusive(expected, :ignore_filter => /Supportability/)
  end

  def test_records_commands_without_args_in_tt_node_for_multi_blocks
    in_transaction do
      @redis.multi do
        @redis.set 'darkpact', 'sorcery'
        @redis.get 'chaos orb'
      end
    end

    tt = last_transaction_trace
    pipeline_node = tt.root_node.called_nodes[0].called_nodes[0]

    assert_equal("multi\nset ?\nget ?\nexec", pipeline_node[:statement])
  end

  def test_records_commands_with_args_in_tt_node_for_multi_blocks
    with_config(:'transaction_tracer.record_redis_arguments' => true) do
      in_transaction do
        @redis.multi do
          @redis.set 'darkpact', 'sorcery'
          @redis.get 'chaos orb'
        end
      end
    end

    tt = last_transaction_trace
    pipeline_node = tt.root_node.called_nodes[0].called_nodes[0]

    assert_equal("multi\nset \"darkpact\" \"sorcery\"\nget \"chaos orb\"\nexec", pipeline_node[:statement])
  end
end
end
