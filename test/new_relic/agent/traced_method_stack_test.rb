# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))
require 'new_relic/agent/traced_method_stack'

class NewRelic::Agent::TracedMethodStackTest < Minitest::Test
  def setup
    @frame_stack = NewRelic::Agent::TracedMethodStack.new
  end

  def test_scope__overlap
    freeze_time

    in_transaction('orlando') do
      self.class.trace_execution_scoped('disney', :deduct_call_time_from_parent => false) { advance_time(0.1) }
    end

    in_transaction('anaheim') do
      self.class.trace_execution_scoped('disney', :deduct_call_time_from_parent => false) { advance_time(0.11) }
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


  def test_scope_failure
    scope1 = @frame_stack.push_frame(:scope1)
    scope2 = @frame_stack.push_frame(:scope2)
    assert_raises(RuntimeError) do
      @frame_stack.pop_frame(scope1, "name 1")
    end
  end

  def test_children_time
    t1 = freeze_time
    expected1 = @frame_stack.push_frame(:a)
    advance_time(0.001)
    t2 = Time.now

    expected2 = @frame_stack.push_frame(:b)
    advance_time(0.002)
    t3 = Time.now

    expected = @frame_stack.push_frame(:c)
    advance_time(0.003)
    scope = @frame_stack.pop_frame(expected, "metric c")

    t4 = Time.now
    assert_equal 0, scope.children_time

    advance_time(0.001)
    t5 = Time.now

    expected = @frame_stack.push_frame(:d)
    advance_time(0.002)
    scope = @frame_stack.pop_frame(expected, "metric d")

    t6 = Time.now

    assert_equal 0, scope.children_time

    scope = @frame_stack.pop_frame(expected2, "metric b")
    assert_equal 'metric b', scope.name

    assert_in_delta((t4 - t3) + (t6 - t5), scope.children_time, 0.0001)

    scope = @frame_stack.pop_frame(expected1, "metric a")
    assert_equal scope.name, 'metric a'

    assert_in_delta((t6 - t2), scope.children_time, 0.0001)
  end


  # test for when the scope stack contains an element only used for tts and not metrics
  def test_simple_tt_only_scope
    node1 = @frame_stack.push_frame(:a, 0, true)
    node2 = @frame_stack.push_frame(:b, 10, false)
    node3 = @frame_stack.push_frame(:c, 20, true)

    @frame_stack.pop_frame(node3, "name a", 30)
    @frame_stack.pop_frame(node2, "name b", 20)
    @frame_stack.pop_frame(node1, "name c", 10)

    assert_equal 0, node3.children_time
    assert_equal 10, node2.children_time
    assert_equal 10, node1.children_time

    assert @frame_stack.empty?
  end

  def test_double_tt_only_scope
    node1 = @frame_stack.push_frame(:a,  0, true)
    node2 = @frame_stack.push_frame(:b, 10, false)
    node3 = @frame_stack.push_frame(:c, 20, false)
    node4 = @frame_stack.push_frame(:d, 30, true)

    @frame_stack.pop_frame(node4, "name d", 40)
    @frame_stack.pop_frame(node3, "name c", 30)
    @frame_stack.pop_frame(node2, "name b", 20)
    @frame_stack.pop_frame(node1, "name a", 10)

    assert_equal  0, node4.children_time.round
    assert_equal 10, node3.children_time.round
    assert_equal 10, node2.children_time.round
    assert_equal 10, node1.children_time.round

    assert @frame_stack.empty?
  end

  def test_sampler_enabling
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => false)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => false, :developer_mode => true)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => true)

    assert_sampler_enabled_with(false, :'transaction_tracer.enabled' => false, :developer_mode => false)
  end

  def assert_sampler_enabled_with(expected, opts={})
    with_config(opts) do
      assert_equal expected, @frame_stack.sampler_enabled?
    end
  end

end

