# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

class NewRelic::Agent::Instrumentation::QueueTimeTest < Minitest::Test
  include NewRelic::Agent::Instrumentation

  def setup
    nr_freeze_process_time
  end

  def teardown
    NewRelic::Agent.drop_buffered_data
  end

  def test_parse_frontend_timestamp_given_queue_start_header
    header = {'HTTP_X_QUEUE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 60)}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_given_request_start_header
    header = {'HTTP_X_REQUEST_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 60)}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_given_middleware_start_header
    header = {'HTTP_X_MIDDLEWARE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 60)}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_from_earliest_header
    headers = {'HTTP_X_REQUEST_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 63),
               'HTTP_X_QUEUE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 62),
               'HTTP_X_MIDDLEWARE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 61)}

    assert_in_delta(seconds_ago(63), QueueTime.parse_frontend_timestamp(headers), 0.001)
  end

  def test_parse_frontend_timestamp_from_earliest_header_out_of_order
    headers = {'HTTP_X_MIDDLEWARE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 63),
               'HTTP_X_REQUEST_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 62),
               'HTTP_X_QUEUE_START' => format_header_time(Process.clock_gettime(Process::CLOCK_REALTIME) - 61)}

    assert_in_delta(seconds_ago(63), QueueTime.parse_frontend_timestamp(headers), 0.001)
  end

  def test_parse_frontend_timestamp_from_header_in_seconds
    header = {'HTTP_X_QUEUE_START' => "t=#{Process.clock_gettime(Process::CLOCK_REALTIME) - 60}"}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_from_header_in_milliseconds
    header = {'HTTP_X_QUEUE_START' => "t=#{(Process.clock_gettime(Process::CLOCK_REALTIME) - 60) * 1_000}"}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_from_header_with_multiple_servers
    now = Process.clock_gettime(Process::CLOCK_REALTIME)
    header = {'HTTP_X_QUEUE_START' => "servera t=#{now - 60}, serverb t=#{now - 30}"}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_from_header_missing_t_equals
    header = {'HTTP_X_REQUEST_START' => (Process.clock_gettime(Process::CLOCK_REALTIME) - 60).to_s}
    assert_in_delta(seconds_ago(60), QueueTime.parse_frontend_timestamp(header), 0.001)
  end

  def test_parse_frontend_timestamp_from_header_negative
    now = Process.clock_gettime(Process::CLOCK_REALTIME)
    the_future = now + 60
    header = {'HTTP_X_REQUEST_START' => the_future.to_s}
    assert_in_delta(now, QueueTime.parse_frontend_timestamp(header, now), 0.001)
  end

  def test_parsing_malformed_header
    header = {'HTTP_X_REQUEST_START' => 'gobledy gook'}

    assert_nil QueueTime.parse_frontend_timestamp(header)
  end

  def test_parse_timestamp_can_identify_unit
    now = Process.clock_gettime(Process::CLOCK_REALTIME)
    assert_in_delta(now, QueueTime.parse_timestamp(now.to_s).to_f, 0.001)
    assert_in_delta(now, QueueTime.parse_timestamp((now * 1_000).to_s).to_f, 0.001)
    assert_in_delta(now, QueueTime.parse_timestamp((now * 1_000_000).to_s).to_f, 0.001)
  end

  def format_header_time(time = Process.clock_gettime(Process::CLOCK_REALTIME))
    "t=#{(time * 1_000_000).to_i}"
  end

  def seconds_ago(seconds)
    Process.clock_gettime(Process::CLOCK_REALTIME) - seconds
  end

  def assert_metric_value_in_delta(expected, metric_name, delta)
    stats_engine = NewRelic::Agent.instance.stats_engine
    stats_engine.clear_stats
    yield
    assert_in_delta(expected, stats_engine.get_stats(metric_name).total_call_time, delta)
  end
end
