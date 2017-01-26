# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))
require 'new_relic/agent/traced_method_stack'
require 'new_relic/agent/transaction/segment'

class NewRelic::Agent::TracedMethodStackTest < Minitest::Test
  def setup
    @frame_stack = NewRelic::Agent::TracedMethodStack.new
  end

  def test_scope_overlap
    freeze_time

    in_transaction('orlando') do
      self.class.trace_execution_scoped('disney') { advance_time(0.1) }
    end

    in_transaction('anaheim') do
      self.class.trace_execution_scoped('disney') { advance_time(0.11) }
    end

    assert_metrics_recorded(
      ['disney', 'orlando'] => {
        :call_count      => 1,
        :total_call_time => 0.1
      },
      ['disney', 'anaheim'] => {
        :call_count      => 1,
        :total_call_time => 0.11
      },
      'disney' => {
        :call_count      => 2,
        :total_call_time => 0.21
      })
  end

  def test_clear
    state = NewRelic::Agent::TransactionState.tl_get

    segment = NewRelic::Agent::Transaction::Segment.new "a"

    @frame_stack.push_segment(state, segment)
    @frame_stack.clear

    assert_empty @frame_stack
  end

  def test_sampler_enabling
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true)
    assert_sampler_enabled_with(false, :'transaction_tracer.enabled' => false)
  end

  def test_fetch_matching_frame_fetches_the_next_matching_frame
    state = NewRelic::Agent::TransactionState.tl_get
    segment = NewRelic::Agent::Transaction::Segment.new "a"
    @frame_stack.push_segment state, segment

    result = @frame_stack.fetch_matching_frame(segment)

    assert_equal "a", result.name
    assert_equal segment, result
  end

  def test_fetch_matching_frame_discards_mismatched_frames
    state = NewRelic::Agent::TransactionState.tl_get
    segment = NewRelic::Agent::Transaction::Segment.new "a"
    @frame_stack.push_segment state, segment

    @frame_stack.push_segment state, NewRelic::Agent::Transaction::Segment.new("b")

    result = @frame_stack.fetch_matching_frame(segment)

    assert_equal "a", result.name
    assert_equal segment, result
  end

  def test_fetch_matching_frame_raises_an_error_if_no_match
    state = NewRelic::Agent::TransactionState.tl_get
    state = NewRelic::Agent::TransactionState.tl_get
    segment = NewRelic::Agent::Transaction::Segment.new "a"
    @frame_stack.push_segment state, segment

    @frame_stack.fetch_matching_frame(segment)

    error = assert_raises(RuntimeError) do
      @frame_stack.fetch_matching_frame(segment)
    end

    assert_match(/not found/, error.message)
  end

  def test_fetch_matching_frame_logs_any_unexpected_frame_tags
    state = NewRelic::Agent::TransactionState.tl_get
    segment = NewRelic::Agent::Transaction::Segment.new "a"
    @frame_stack.push_segment state, segment

    @frame_stack.push_segment state, NewRelic::Agent::Transaction::Segment.new("unexpected")

    expects_logging(:info, includes("unexpected"))

    @frame_stack.fetch_matching_frame(segment)
  end

  def assert_sampler_enabled_with(expected, opts={})
    with_config(opts) do
      assert_equal expected, @frame_stack.sampler_enabled?
    end
  end

end

