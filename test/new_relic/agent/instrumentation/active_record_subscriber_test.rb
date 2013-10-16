# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

MIN_RAILS_VERSION = 4

if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i >= MIN_RAILS_VERSION && !NewRelic::LanguageSupport.using_engine?('jruby')

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_record_subscriber'

class NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest < Test::Unit::TestCase
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
    freeze_time

    simulate_query(2)

    metric_name = 'ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_recorded(
      metric_name => { :call_count => 1, :total_call_time => 2.0 }
    )
  end

  def test_records_scoped_metrics
    freeze_time

    in_transaction('test_txn') { simulate_query(2) }

    metric_name = 'ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_recorded(
      [metric_name, 'test_txn'] => { :call_count => 1, :total_call_time => 2 }
    )
  end

  def test_records_nothing_if_tracing_disabled
    freeze_time

    NewRelic::Agent.disable_all_tracing { simulate_query(2) }

    metric_name = 'ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'
    assert_metrics_not_recorded([metric_name])
  end

  def test_records_rollup_metrics
    freeze_time

    in_web_transaction { simulate_query(2) }

    assert_metrics_recorded(
      'ActiveRecord/find' => { :call_count => 1, :total_call_time => 2 },
      'ActiveRecord/all' => { :call_count => 1, :total_call_time => 2 }
    )
  end

  def test_records_remote_service_metric
    connection_pool = stub(:connections => [ @connection ])
    connection_pool_list = [connection_pool]
    ::ActiveRecord::Base.connection_handler.stubs(:connection_pool_list).returns(connection_pool_list)

    freeze_time

    simulate_query(2)

    assert_metrics_recorded(
      'RemoteService/sql/mysql/server' => { :call_count => 1, :total_call_time => 2.0 }
    )
  end

  def test_creates_txn_segment
    freeze_time

    NewRelic::Agent.manual_start
    @stats_engine.start_transaction
    sampler = NewRelic::Agent.instance.transaction_sampler
    sampler.notice_first_scope_push(Time.now.to_f)
    sampler.notice_transaction('/path', {})
    sampler.notice_push_scope('Controller/sandwiches/index')
    simulate_query(2)
    sampler.notice_pop_scope('Controller/sandwiches/index')
    sampler.notice_scope_empty(stub('txn', :name => '/path', :custom_parameters => {}))

    last_segment = nil
    sampler.last_sample.root_segment.each_segment{|s| last_segment = s }
    NewRelic::Agent.shutdown

    assert_equal('ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find',
                 last_segment.metric_name)
    assert_equal('SELECT * FROM sandwiches',
                 last_segment.params[:sql])
  end

  def test_creates_slow_sql_node
    NewRelic::Agent.manual_start
    sampler = NewRelic::Agent.instance.sql_sampler
    sampler.notice_first_scope_push nil
    freeze_time

    simulate_query(2)

    assert_equal 'SELECT * FROM sandwiches', sampler.transaction_data.sql_data[0].sql
  ensure
    NewRelic::Agent.shutdown
  end

  def test_should_not_raise_due_to_an_exception_during_instrumentation_callback
    @subscriber.stubs(:record_metrics).raises(StandardError)
    assert_nothing_raised { simulate_query }
  end

  def simulate_query(duration=nil)
    @subscriber.start('sql.active_record', :id, @params)
    advance_time(duration) if duration
    @subscriber.finish('sql.active_record', :id, @params)
  end

  def test_active_record_config_for_event
    target_connection = ActiveRecord::Base.connection_handler.connection_pool_list.first.connections.first
    expected_config = target_connection.instance_variable_get(:@config)

    event = mock('event')
    event.stubs(:payload).returns({ :connection_id => target_connection.object_id })

    result = @subscriber.active_record_config_for_event(event)
    assert_equal expected_config, result
  end
end

else
  puts "Skipping tests in #{__FILE__} because Rails >= #{MIN_RAILS_VERSION} is unavailable"
end
