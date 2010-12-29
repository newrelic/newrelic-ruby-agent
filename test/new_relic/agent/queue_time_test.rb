require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
class QueueTimeTest < Test::Unit::TestCase
  require 'new_relic/agent/instrumentation/queue_time'
  include NewRelic::Agent::Instrumentation::QueueTime
  
  def setup
    NewRelic::Agent.instance.stats_engine.clear_stats
  end
  
  # test helper method
  def check_metric(metric, value, delta)
    time = NewRelic::Agent.get_stats(metric).total_call_time
    assert_between (value - delta), (value + delta), time, "Metric #{metric} not in expected range: was #{time} but expected in #{value - delta} to #{value + delta}!"
  end

  # initial base case, a router and a static content server
  def test_parse_queue_time_from_initial
    env = {}
    time1 = ((Time.now - 2).to_f * 1_000_000.0).to_i
    time2 = ((Time.now - 1).to_f * 1_000_000.0).to_i
    env['HTTP_X_REQUEST_START'] = "servera t=#{time1}, serverb t=#{time2}"
    assert_calls_metrics('WebFrontend/WebServer/all', 'WebFrontend/WebServer/servera', 'WebFrontend/WebServer/serverb') do
      parse_queue_time_from(env)
    end
    check_metric('WebFrontend/WebServer/all', 2.0, 0.1)
    check_metric('WebFrontend/WebServer/servera', 1.0, 0.1)
    check_metric('WebFrontend/WebServer/serverb', 1.0, 0.1)
  end
  
  # test for backwards compatibility with old header
  def test_parse_queue_time_from_with_no_server_name
    assert_calls_metrics('WebFrontend/WebServer/all') do
      parse_queue_time_from({'HTTP_X_REQUEST_START' => "t=#{convert_to_microseconds(Time.now) - 1000000}"})
    end
    check_metric('WebFrontend/WebServer/all', 1.0, 0.1)
  end

  def test_parse_queue_time_from_with_no_header
    assert_calls_metrics('WebFrontend/WebServer/all') do
      parse_queue_time_from({})
    end
  end

  # each server should be one second, and the total would be 2 seconds
  def test_record_individual_server_stats
    matches = [['foo', Time.at(1000)], ['bar', Time.at(1001)]]
    assert_calls_metrics('WebFrontend/WebServer/foo', 'WebFrontend/WebServer/bar') do
      record_individual_server_stats(Time.at(1002), matches)
    end
    check_metric('WebFrontend/WebServer/foo', 1.0, 0.1)
    check_metric('WebFrontend/WebServer/bar', 1.0, 0.1)
  end

  def test_record_rollup_stat
    assert_calls_metrics('WebFrontend/WebServer/all') do
      record_rollup_stat(Time.at(1001), [['a', Time.at(1000)]])
    end
    check_metric('WebFrontend/WebServer/all', 1.0, 0.1)
  end

  def test_record_rollup_stat_no_data
    assert_calls_metrics('WebFrontend/WebServer/all') do
      record_rollup_stat(Time.at(1001), [])
    end
    check_metric('WebFrontend/WebServer/all', 0.0, 0.001)
  end
  
  # check all the combinations to make sure that ordering doesn't
  # affect the return value
  def test_find_oldest_time
    test_arrays = [
                   ['a', Time.at(1000)],
                   ['b', Time.at(1001)],
                   ['c', Time.at(1002)],
                   ['d', Time.at(1000)],
                  ]
    test_arrays = test_arrays.permutation
    test_arrays.each do |test_array|
      assert_equal find_oldest_time(test_array), Time.at(1000), "Should be the oldest time in the array"
    end
  end

  # trivial test but the method doesn't do much
  def test_record_queue_time_for
    name = 'foo'
    time = Time.at(1000)
    start_time = Time.at(1001)
    self.expects(:record_time_stat).with('WebFrontend/WebServer/foo', time, start_time)
    record_queue_time_for(name, time, start_time)
  end

  def test_record_time_stat
    assert_calls_metrics('WebFrontend/WebServer/foo') do
      record_time_stat('WebFrontend/WebServer/foo', Time.at(1000), Time.at(1001))
    end
    check_metric('WebFrontend/WebServer/foo', 1.0, 0.1)
    assert_raises(RuntimeError) do
      record_time_stat('foo', Time.at(1001), Time.at(1000))
    end
  end

    def test_convert_to_microseconds
    assert_equal((1_000_000_000), convert_to_microseconds(Time.at(1000)), 'time at 1000 seconds past epoch should be 1,000,000,000 usec')
    assert_equal 1_000_000_000, convert_to_microseconds(1_000_000_000), 'should not mess with a number if passed in'
    assert_raises(TypeError) do
      convert_to_microseconds('whoo yeah buddy')
    end
  end

  def test_convert_from_microseconds
    assert_equal Time.at(1000), convert_from_microseconds(1_000_000_000), 'time at 1,000,000,000 usec should be 1000 seconds after epoch'
    assert_equal Time.at(1000), convert_from_microseconds(Time.at(1000)), 'should not mess with a time passed in'
    assert_raises(TypeError) do
      convert_from_microseconds('10000000000')
    end
  end
end
