# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/rails4/active_record'

if ::Rails::VERSION::MAJOR.to_i >= 4 && !NewRelic::LanguageSupport.using_engine?('jruby')
class NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest < Test::Unit::TestCase
  class Order; end

  def setup
    @config = { :adapter => 'mysql', :host => 'server' }
    @connection = Object.new
    @connection.instance_variable_set(:@config, @config)
    Order.stubs(:connection_pool).returns(stub(:connections => [ @connection ]))

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
    t1 = Time.now
    t0 = t1 - 2
    @subscriber.call('sql.active_record', t0, t1, :id, @params)

    metric_name = 'ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'

    metric = @stats_engine.lookup_stats(metric_name)
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_records_scoped_metrics
    t1 = Time.now
    t0 = t1 - 2

    @stats_engine.start_transaction('test_txn')
    @subscriber.call('sql.active_record', t0, t1, :id, @params)

    metric_name = 'ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find'

    scoped_metric = @stats_engine.lookup_stats(metric_name, 'test_txn')
    assert_equal(1, scoped_metric.call_count)
    assert_equal(2.0, scoped_metric.total_call_time)
  end

  def test_records_nothing_if_tracing_disabled
    t1 = Time.now
    t0 = t1 - 2

    NewRelic::Agent.disable_all_tracing do
      @subscriber.call('sql.active_record', t0, t1, :id, @params)
    end

    metric = @stats_engine \
      .lookup_stats('ActiveRecord/NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order/find')
    assert_nil metric
  end

  def test_records_rollup_metrics
    t1 = Time.now
    t0 = t1 - 2

    @subscriber.call('sql.active_record', t0, t1, :id, @params)

    ['ActiveRecord/find', 'ActiveRecord/all'].each do |metric_name|
      metric = @stats_engine.lookup_stats(metric_name)
      assert_equal(1, metric.call_count,
                   "Incorrect call count for #{metric_name}")
      assert_equal(2.0, metric.total_call_time,
                   "Incorrect call time for #{metric_name}")
    end
  end

  def test_records_remote_service_metric
    t1 = Time.now
    t0 = t1 - 2

    @subscriber.call('sql.active_record', t0, t1, :id, @params)

    metric = @stats_engine.lookup_stats('RemoteService/sql/mysql/server')
    assert_equal(1, metric.call_count)
    assert_equal(2.0, metric.total_call_time)
  end

  def test_creates_txn_segment
    t1 = Time.now
    t0 = t1 - 2

    NewRelic::Agent.manual_start
    @stats_engine.start_transaction('test')
    sampler = NewRelic::Agent.instance.transaction_sampler
    sampler.notice_first_scope_push(Time.now.to_f)
    sampler.notice_transaction('/path', '/path', {})
    sampler.notice_push_scope('Controller/sandwiches/index')
    @subscriber.call('sql.active_record', t0, t1, :id, @params)
    sampler.notice_pop_scope('Controller/sandwiches/index')
    sampler.notice_scope_empty

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
    t1 = Time.now
    t0 = t1 - 2

    @subscriber.call('sql.active_record', t0, t1, :id, @params)

    assert_equal 'SELECT * FROM sandwiches', sampler.transaction_data.sql_data[0].sql
  ensure
    NewRelic::Agent.shutdown
  end
end
end
