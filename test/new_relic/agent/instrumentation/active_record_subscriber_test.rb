# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

MIN_RAILS_VERSION = 4

if defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR.to_i >= MIN_RAILS_VERSION && !NewRelic::LanguageSupport.jruby?

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_subscriber'

class NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest < Minitest::Test
  class Order; end

  def setup
    @config = { :adapter => 'mysql', :host => 'server' }
    @connection = Object.new
    @connection.instance_variable_set(:@config, @config)


    @params = {
      :name => 'NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order Load',
      :sql => 'SELECT * FROM sandwiches',
      :connection_id => @connection.object_id
    }

    @subscriber = NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new

    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
  end

  def test_records_metrics_for_simple_find
    nr_freeze_time

    in_transaction('test_txn') { simulate_query(2) }

    metric_name = 'Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_recorded(
      metric_name => { :call_count => 1, :total_call_time => 2.0 }
    )
  end

  def test_records_scoped_metrics
    nr_freeze_time

    in_transaction('test_txn') { simulate_query(2) }

    metric_name = 'Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_recorded(
      [metric_name, 'test_txn'] => { :call_count => 1, :total_call_time => 2 }
    )
  end

  def test_records_datastore_instance_metric_for_supported_adapter
    config = { :adapter => "mysql", :host => "jonan.gummy_planet", :port => 3306 }
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_recorded('Datastore/instance/MySQL/jonan.gummy_planet/3306')
  end

  def test_records_datastore_instance_metric_with_one_datum_missing
    config = { :adapter => "mysql", :host => "jonan.gummy_planet", :port => "" }
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_recorded('Datastore/instance/MySQL/jonan.gummy_planet/unknown')

    config = { :adapter => "mysql", :host => "", :port => 3306 }
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_recorded('Datastore/instance/MySQL/unknown/3306')
  end

  def test_does_not_record_datastore_instance_metric_for_unsupported_adapter
    config = { :adapter => "JonanDB", :host => "jonan.gummy_planet" }
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_not_recorded('Datastore/instance/JonanDB/jonan.gummy_planet/default')
  end

  def test_does_not_record_datastore_instance_metric_if_disabled
    with_config('datastore_tracer.instance_reporting.enabled' => false) do
      config = { :host => "jonan.gummy_planet" }
      @subscriber.stubs(:active_record_config).returns(config)

      in_transaction('test_txn') { simulate_query(2) }

      assert_metrics_not_recorded('Datastore/instance/ActiveRecord/jonan.gummy_planet/default')
    end
  end

  def test_does_not_record_datastore_instance_metric_if_both_are_empty
    config = { :adapter => "", :host => "" }
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_not_recorded('Datastore/instance/unknown/unknown')
  end

  def test_does_not_record_database_name_if_disabled
    config = { :host => "jonan.gummy_planet", :database => "pizza_cube" }
    @subscriber.stubs(:active_record_config).returns(config)
    with_config('datastore_tracer.database_name_reporting.enabled' => false) do
      in_transaction { simulate_query(2) }
    end
    sample = last_transaction_trace
    node = find_node_with_name_matching sample, /Datastore\//
    refute node.params.key?(:database_name)
  end

  def test_records_unknown_unknown_when_error_gathering_instance_data
    NewRelic::Agent::Instrumentation::ActiveRecordHelper::InstanceIdentification.stubs(:postgres_unix_domain_socket_case?).raises StandardError.new
    NewRelic::Agent::Instrumentation::ActiveRecordHelper::InstanceIdentification.stubs(:mysql_default_case?).raises StandardError.new

    config = {:adapter => 'mysql', :host => "127.0.0.1"}
    @subscriber.stubs(:active_record_config).returns(config)

    in_transaction('test_txn') { simulate_query(2) }

    assert_metrics_recorded("Datastore/instance/MySQL/unknown/unknown")
  end

  def test_records_nothing_if_tracing_disabled
    nr_freeze_time

    in_transaction('test_txn') do
      NewRelic::Agent.disable_all_tracing { simulate_query(2) }
    end

    metric_name = 'Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_not_recorded([metric_name])
  end

  def test_records_rollup_metrics
    nr_freeze_time

    in_web_transaction { simulate_query(2) }

    assert_metrics_recorded(
      'Datastore/operation/ActiveRecord/find' => { :call_count => 1, :total_call_time => 2 },
      'Datastore/allWeb' => { :call_count => 1, :total_call_time => 2 },
      'Datastore/all' => { :call_count => 1, :total_call_time => 2 }
    )
  end

  def test_creates_txn_node
    nr_freeze_time

    in_transaction do
      simulate_query(2)
    end

    last_node = nil
    last_transaction_trace.root_node.each_node{|s| last_node = s }

    assert_equal('Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find',
                 last_node.metric_name)
    assert_equal('SELECT * FROM sandwiches',
                 last_node.params[:sql].sql)
  end

  def test_creates_slow_sql_node
    nr_freeze_time

    sampler = NewRelic::Agent.instance.sql_sampler
    sql = nil

    in_transaction do
      simulate_query(2)
      sql = sampler.tl_transaction_data.sql_data[0].sql
    end

    assert_equal 'SELECT * FROM sandwiches', sql
  end

  def test_should_not_raise_due_to_an_exception_during_instrumentation_callback
    @subscriber.stubs(:record_metrics).raises(StandardError)
    simulate_query
  end

  def test_active_record_config_for_event
    target_connection = ActiveRecord::Base.connection_handler.connection_pool_list.first.connections.first
    expected_config = target_connection.instance_variable_get(:@config)

    payload = { :connection_id => target_connection.object_id }

    result = @subscriber.active_record_config(payload)
    assert_equal expected_config, result
  end

  def test_segment_created
    in_transaction 'test' do
      txn = NewRelic::Agent::Tracer.current_transaction
      assert_equal 1, txn.segments.size

      simulate_query 1
      assert_equal 2, txn.segments.size
      assert txn.segments.last.finished?, "Segment '#{txn.segments.last.name}'' was never finished.  "
      assert_equal \
        'Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find',
        txn.segments.last.name

      simulate_query 1
      assert_equal 3, txn.segments.size
      assert txn.segments.last.finished?, "Segment '#{txn.segments.last.name}'' was never finished.  "
      assert_equal \
        'Datastore/statement/ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find',
        txn.segments.last.name
    end
  end

  private

  def simulate_query(duration=nil)
    @subscriber.start('sql.active_record', :id, @params)
    advance_time(duration) if duration
    @subscriber.finish('sql.active_record', :id, @params)
  end
end

else
  puts "Skipping tests in #{__FILE__} because Rails >= #{MIN_RAILS_VERSION} is unavailable"
end
