# https://newrelic.atlassian.net/browse/RUBY-765
require 'fake_collector'

class HttpResponseCodeTest < Test::Unit::TestCase
  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run
    NewRelic::Agent.manual_start(:send_data_on_exit => false)
    @agent = NewRelic::Agent.instance
  end

  def teardown
    $collector.reset
    NewRelic::Agent.shutdown
  end

  def test_request_entity_too_large
    $collector.mock['metric_data'] = [413, {'exception' => {'error_type' => 'RuntimeError', 'message' => 'too much'}}]

    @agent.stats_engine.get_stats_no_scope('Custom/too_big') \
      .record_data_point(1)
    assert_equal 1, @agent.stats_engine \
      .get_stats_no_scope('Custom/too_big').call_count

    @agent.send(:harvest_and_send_timeslice_data)

    # make sure the data gets thrown away without crashing
    assert_equal 0, @agent.stats_engine \
      .get_stats_no_scope('Custom/too_big').call_count

    # make sure we actually talked to the collector
    assert_equal(1, $collector.agent_data.select{|x| x.action == 'metric_data'}.size)
  end

  def test_unsupported_media_type
    $collector.mock['metric_data'] = [415, {'exception' => {'error_type' => 'RuntimeError', 'message' => 'looks bad'}}]

    @agent.stats_engine.get_stats_no_scope('Custom/too_big') \
      .record_data_point(1)
    assert_equal 1, @agent.stats_engine \
      .get_stats_no_scope('Custom/too_big').call_count

    @agent.send(:harvest_and_send_timeslice_data)

    # make sure the data gets thrown away without crashing
    assert_equal 0, @agent.stats_engine \
      .get_stats_no_scope('Custom/too_big').call_count

    # make sure we actually talked to the collector
    assert_equal(1, $collector.agent_data.select{|x| x.action == 'metric_data'}.size)
  end
end
