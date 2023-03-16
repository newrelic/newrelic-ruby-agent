# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

class NewRelic::Agent::StatsTest < Minitest::Test
  def mock_plusequals(first, second, method, first_value, second_value)
    first.expects(method).returns(first_value)
    second.expects(method).returns(second_value)
    first.expects("#{method}=".to_sym).with(first_value + second_value)
  end

  def test_update_totals
    attrs = [:total_call_time, :total_exclusive_time, :sum_of_squares]
    merged = setup_merge do |a, b|
      attrs.each do |attr|
        a.send("#{attr}=", 2)
        b.send("#{attr}=", 3)
      end
    end

    attrs.each do |attr|
      assert_equal(5, merged.send(attr))
    end
  end

  def setup_merge
    a = NewRelic::Agent::Stats.new
    b = NewRelic::Agent::Stats.new
    a.reset
    b.reset
    yield(a, b)
    a.merge(b)
  end

  def test_merge_expands_min_max_call_time
    merged = setup_merge do |a, b|
      a.call_count = 1
      b.call_count = 1
      a.min_call_time = 0.5
      a.max_call_time = 3.0
      b.min_call_time = 1.0
      b.max_call_time = 4.0
    end

    assert_in_delta(0.5, merged.min_call_time)
    assert_in_delta(4.0, merged.max_call_time)
  end

  def test_simple
    stats = NewRelic::Agent::Stats.new
    validate(stats: stats, count: 0, total: 0, min: 0, max: 0)

    assert_equal 0, stats.call_count
    stats.trace_call(10)
    stats.trace_call(20)
    stats.trace_call(30)

    validate(stats: stats, count: 3, total: (10 + 20 + 30), min: 10, max: 30)
  end

  def test_to_s
    s1 = NewRelic::Agent::Stats.new
    s1.trace_call(10)

    assert_equal('[ 1 calls 10.0000s / 10.0000s ex]', s1.to_s)
  end

  def test_apdex_recording
    s = NewRelic::Agent::Stats.new

    s.record_apdex(:apdex_s, 1)
    s.record_apdex(:apdex_t, 1)

    s.record_apdex(:apdex_f, 1)
    s.record_apdex(:apdex_t, 1)

    assert_equal(1, s.apdex_s)
    assert_equal(1, s.apdex_f)
    assert_equal(2, s.apdex_t)
  end

  def test_merge
    s1 = NewRelic::Agent::Stats.new
    s2 = NewRelic::Agent::Stats.new

    s1.trace_call(10)
    s2.trace_call(20)
    s2.freeze

    validate(stats: s2, count: 1, total: 20, min: 20, max: 20)
    s3 = s1.merge(s2)
    validate(stats: s3, count: 2, total: (10 + 20), min: 10, max: 20)
    validate(stats: s1, count: 1, total: 10, min: 10, max: 10)
    validate(stats: s2, count: 1, total: 20, min: 20, max: 20)

    s1.merge!(s2)
    validate(stats: s1, count: 2, total: (10 + 20), min: 10, max: 20)
    validate(stats: s2, count: 1, total: 20, min: 20, max: 20)
  end

  def test_merge_with_exclusive
    s1 = NewRelic::Agent::Stats.new

    s2 = NewRelic::Agent::Stats.new

    s1.trace_call(10, 5)
    s2.trace_call(20, 10)
    s2.freeze

    validate(stats: s2, count: 1, total: 20, min: 20, max: 20, exclusive: 10)
    s3 = s1.merge(s2)
    validate(stats: s3, count: 2, total: (10 + 20), min: 10, max: 20, exclusive: (10 + 5))
    validate(stats: s1, count: 1, total: 10, min: 10, max: 10, exclusive: 5)
    validate(stats: s2, count: 1, total: 20, min: 20, max: 20, exclusive: 10)

    s1.merge!(s2)
    validate(stats: s1, count: 2, total: (10 + 20), min: 10, max: 20, exclusive: (5 + 10))
    validate(stats: s2, count: 1, total: 20, min: 20, max: 20, exclusive: 10)
  end

  def test_hash_merge
    incomplete_stats_hash = {
      :count => 12,
      :max => 5,
      :sum_of_squares => 999
    }

    stats = NewRelic::Agent::Stats.new
    stats = stats.hash_merge(incomplete_stats_hash)
    validate(stats: stats, count: 12, total: 0.0, min: 0.0, max: 5, exclusive: 0.0, sum_of_squares: 999)
  end

  def test_freeze
    s1 = NewRelic::Agent::Stats.new

    s1.trace_call(10)
    s1.freeze

    begin
      # the following should throw an exception because s1 is frozen
      s1.trace_call(20)

      assert false
    rescue StandardError
      assert_predicate s1, :frozen?
      validate(stats: s1, count: 1, total: 10, min: 10, max: 10)
    end
  end

  def test_sum_of_squares_merge
    s1 = NewRelic::Agent::Stats.new
    s1.trace_call(4)
    s1.trace_call(7)

    s2 = NewRelic::Agent::Stats.new
    s2.trace_call(13)
    s2.trace_call(16)

    s3 = s1.merge(s2)

    assert_equal(s1.sum_of_squares, 4 * 4 + 7 * 7)
    assert_equal(s3.sum_of_squares, 4 * 4 + 7 * 7 + 13 * 13 + 16 * 16, 'check sum of squares')
  end

  def test_to_json_enforces_float_values
    s1 = NewRelic::Agent::Stats.new
    s1.trace_call(3.to_r)
    s1.trace_call(7.to_r)

    assert_in_delta(3.0, JSON.load(s1.to_json)['min_call_time'])
  end

  private

  def validate(stats:, count:, total:, min:, max:, sum_of_squares: nil, exclusive: nil)
    assert_equal count, stats.call_count
    assert_equal total, stats.total_call_time
    assert_equal min, stats.min_call_time
    assert_equal max, stats.max_call_time
    assert_equal exclusive, stats.total_exclusive_time if exclusive
  end
end
