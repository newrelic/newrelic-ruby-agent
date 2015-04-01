# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper.rb', __FILE__)
require 'new_relic/agent/transaction/trace'

class NewRelic::Agent::Transaction::TraceTest < Minitest::Test
  def setup
    freeze_time
    @start_time = Time.now
    @trace = NewRelic::Agent::Transaction::Trace.new(@start_time)
  end

  def test_start_time
    assert_equal @start_time, @trace.start_time
  end

  def test_to_collector_array_includes_start_time
    expected = NewRelic::Helper.time_to_millis(@start_time)
    assert_collector_array_contains(:start_time, expected)
  end

  def assert_collector_array_contains(key, expected)
    indices = { :start_time => 0 }
    assert_equal expected, @trace.to_collector_array[indices[key]]
  end
end
