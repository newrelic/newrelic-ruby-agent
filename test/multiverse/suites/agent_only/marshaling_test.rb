# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/wiki/display/eng/The+Terror+and+Glory+of+Transaction+Traces
# https://newrelic.atlassian.net/browse/RUBY-914

class MarshalingTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start(:'transaction_tracer.transaction_threshold' => 0.0)
    @agent = NewRelic::Agent.instance
    @sampler = @agent.transaction_sampler

    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.mock['connect'] = [200, {'return_value' => { 'agent_run_id' => 666 }}]
    $collector.run
  end

  def teardown
    Thread.current[:transaction_sample_builder] = nil
    $collector.reset
  end

  def test_transaction_trace_marshaling
    # create fake transaction trace
    time = Time.now.to_f
    @sampler.notice_first_scope_push time
    @sampler.notice_transaction '/path', nil, {}
    @sampler.notice_push_scope "a"
    @sampler.notice_push_scope "ab"
    sleep 1
    @sampler.notice_pop_scope "ab"
    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty

    expected_sample = @sampler.instance_variable_get(:@slowest_sample)

    @agent.service.connect
    @agent.send(:harvest_and_send_slowest_sample)

    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
    else
      marshaller = NewRelic::Agent::NewRelicService::PrubyMarshaller.new
    end

    assert_equal('666', $collector.calls_for('transaction_sample_data')[0].run_id)
    assert_equal(expected_sample.to_collector_array(marshaller.default_encoder),
                 $collector.calls_for('transaction_sample_data')[0][1][0])
  end

  def test_metric_data_marshalling
    stats = NewRelic::Agent.instance.stats_engine.get_stats_no_scope('Custom/test/method')
    stats.record_data_point(1.0)
    stats.record_data_point(2.0, 1.0)
    expected = [ 2, 3.0, 2.0, 1.0, 2.0, 5.0 ]

    @agent.service.connect
    @agent.send(:harvest_and_send_timeslice_data)

    assert_equal('666', $collector.calls_for('metric_data')[0].run_id)

    custom_metric = $collector.reported_stats_for_metric('Custom/test/method')[0]
    assert_equal(expected, custom_metric)
  end

  def test_error_data_marshalling
    @agent.error_collector.notice_error(Exception.new('test error'))
    @agent.service.connect
    @agent.send(:harvest_and_send_errors)

    assert_equal('666', $collector.calls_for('error_data')[0].run_id)

    error_data = $collector.calls_for('error_data')[0][1][0]
    assert_equal('test error', error_data[2])
  end

  def test_sql_trace_data_marshalling
    @agent.sql_sampler.notice_first_scope_push(nil)
    @agent.sql_sampler.notice_sql("select * from test",
                                  "Database/test/select",
                                  nil, 1.5)
    @agent.sql_sampler.notice_scope_empty

    @agent.service.connect
    @agent.send(:harvest_and_send_slowest_sql)

    sql_data = $collector.calls_for('sql_trace_data')[0][0]
    assert_equal('select * from test', sql_data[0][3])
  end

  def test_connect_marshalling
    @agent.service.connect('pid' => 1, 'agent_version' => '9000',
                           'app_name' => 'test')

    connect_data = $collector.calls_for('connect')[0]
    assert_equal '9000', connect_data['agent_version']
  end
end
