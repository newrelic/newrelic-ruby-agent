# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))
require 'new_relic/agent/traced_method_stack'

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

  def test_children_time
    state = NewRelic::Agent::TransactionState.tl_get

    freeze_time
    expected1 = @frame_stack.push_frame(state, :a)
    advance_time(0.001)
    t2 = Time.now

    expected2 = @frame_stack.push_frame(state, :b)
    advance_time(0.002)
    t3 = Time.now

    expected = @frame_stack.push_frame(state, :c)
    advance_time(0.003)
    scope = @frame_stack.pop_frame(state, expected, "metric c", Time.now.to_f)

    t4 = Time.now
    assert_equal 0, scope.children_time

    advance_time(0.001)
    t5 = Time.now

    expected = @frame_stack.push_frame(state, :d)
    advance_time(0.002)
    scope = @frame_stack.pop_frame(state, expected, "metric d", Time.now.to_f)

    t6 = Time.now

    assert_equal 0, scope.children_time

    scope = @frame_stack.pop_frame(state, expected2, "metric b", Time.now.to_f)
    assert_equal 'metric b', scope.name

    assert_in_delta((t4 - t3) + (t6 - t5), scope.children_time, 0.0001)

    scope = @frame_stack.pop_frame(state, expected1, "metric a", Time.now.to_f)
    assert_equal scope.name, 'metric a'

    assert_in_delta((t6 - t2), scope.children_time, 0.0001)
  end


  # test for when the scope stack contains an element only used for tts and not metrics
  def test_simple_tt_only_scope
    state = NewRelic::Agent::TransactionState.tl_get

    node1 = @frame_stack.push_frame(state, :a, 0)
    node2 = @frame_stack.push_frame(state, :b, 10)
    node3 = @frame_stack.push_frame(state, :c, 20)

    @frame_stack.pop_frame(state, node3, "name a", 30)
    @frame_stack.pop_frame(state, node2, "name b", 20)
    @frame_stack.pop_frame(state, node1, "name c", 10)

    assert_equal 0, node3.children_time
    assert_equal 10, node2.children_time
    assert_equal 10, node1.children_time

    assert @frame_stack.empty?
  end

  def test_double_tt_only_scope
    state = NewRelic::Agent::TransactionState.tl_get

    node1 = @frame_stack.push_frame(state, :a,  0)
    node2 = @frame_stack.push_frame(state, :b, 10)
    node3 = @frame_stack.push_frame(state, :c, 20)
    node4 = @frame_stack.push_frame(state, :d, 30)

    @frame_stack.pop_frame(state, node4, "name d", 40)
    @frame_stack.pop_frame(state, node3, "name c", 30)
    @frame_stack.pop_frame(state, node2, "name b", 20)
    @frame_stack.pop_frame(state, node1, "name a", 10)

    assert_equal  0, node4.children_time.round
    assert_equal 10, node3.children_time.round
    assert_equal 10, node2.children_time.round
    assert_equal 10, node1.children_time.round

    assert @frame_stack.empty?
  end

  def test_clear
    state = NewRelic::Agent::TransactionState.tl_get

    @frame_stack.push_frame(state, :a)
    @frame_stack.clear
    assert_empty @frame_stack
  end

  def test_sampler_enabling
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => false)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => false, :developer_mode => true)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => true)

    assert_sampler_enabled_with(false, :'transaction_tracer.enabled' => false, :developer_mode => false)
  end

  def test_fetch_matching_frame_fetches_the_next_matching_frame
    state = NewRelic::Agent::TransactionState.tl_get
    frame = @frame_stack.push_frame(state, :a,  0)

    result = @frame_stack.fetch_matching_frame(frame)

    assert_equal :a, result.tag
    assert_equal frame, result
  end

  def test_fetch_matching_frame_discards_mismatched_frames
    state = NewRelic::Agent::TransactionState.tl_get
    frame = @frame_stack.push_frame(state, :a,  0)
    @frame_stack.push_frame(state, :b,  0)

    result = @frame_stack.fetch_matching_frame(frame)

    assert_equal :a, result.tag
    assert_equal frame, result
  end

  def test_fetch_matching_frame_raises_an_error_if_no_match
    state = NewRelic::Agent::TransactionState.tl_get
    frame = @frame_stack.push_frame(state, :a,  0)
    @frame_stack.fetch_matching_frame(frame)

    error = assert_raises(RuntimeError) do
      @frame_stack.fetch_matching_frame(frame)
    end

    assert_match(/not found/, error.message)
  end

  def test_fetch_matching_frame_logs_any_unexpected_frame_tags
    state = NewRelic::Agent::TransactionState.tl_get
    frame = @frame_stack.push_frame(state, :a,  0)
    @frame_stack.push_frame(state, :unexpected,  0)

    expects_logging(:info, includes("unexpected"))

    @frame_stack.fetch_matching_frame(frame)
  end

  def assert_sampler_enabled_with(expected, opts={})
    with_config(opts) do
      assert_equal expected, @frame_stack.sampler_enabled?
    end
  end

end

