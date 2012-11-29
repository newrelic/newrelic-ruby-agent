# https://newrelic.atlassian.net/wiki/display/eng/The+Terror+and+Glory+of+Transaction+Traces
# https://newrelic.atlassian.net/browse/RUBY-914

class MarshalingTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start(:'transaction_tracer.transaction_threshold' => 0.0)
    @agent = NewRelic::Agent.instance
    @sampler = @agent.transaction_sampler

    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      $collector.mock['connect'] = [200, '{"agent_run_id": 666}']
    else
      $collector.mock['connect'] = [200, { 'agent_run_id' => 666 }]
    end
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

    assert_equal(666,
                 $collector.agent_data.select{|x| x.action == 'transaction_sample_data'}[0].body[0])
    assert_equal(expected_sample.to_collector_array(marshaller),
                 $collector.agent_data.select{|x| x.action == 'transaction_sample_data'}[0].body[1][0])
  end

  def test_metric_data_marshalling
    stats = NewRelic::Agent.instance.stats_engine.get_stats_no_scope('Custom/test/method')
    stats.record_data_point(1.0)
    stats.record_data_point(2.0, 1.0)
    expected = [ [ {'name' => 'Custom/test/method', 'scope' => ''},
                           [2, 3.0, 2.0, 1.0, 2.0, 5.0] ] ]

    @agent.service.connect
    @agent.send(:harvest_and_send_timeslice_data)

    assert_equal(666,
       $collector.agent_data.select{|x| x.action == 'metric_data'}[0].body[0])

    metric_data = $collector.agent_data \
      .select{|x| x.action == 'metric_data'}[0].body[3]
    assert metric_data

    custom_metric = metric_data \
      .select{|m| m[0]['name'] == 'Custom/test/method' }
    assert_equal(expected, custom_metric)
  end

  def test_error_data_marshalling
    @agent.error_collector.notice_error(Exception.new('test error'))
    @agent.service.connect
    @agent.send(:harvest_and_send_errors)

    assert_equal(666,
       $collector.agent_data.select{|x| x.action == 'error_data'}[0].body[0])

    error_data = $collector.agent_data \
      .select{|x| x.action == 'error_data'}[0].body[1][0]
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

    sql_data = $collector.agent_data \
      .select{|x| x.action == 'sql_trace_data'}[0].body[0]
    assert_equal('select * from test', sql_data[0][3])
  end

  def test_connect_marshalling
    @agent.service.connect('pid' => 1, 'agent_version' => '9000',
                           'app_name' => 'test')

    connect_data = $collector.agent_data \
      .select{|x| x.action == 'connect'}[0].body[0]
    assert_equal '9000', connect_data['agent_version']
  end
end

