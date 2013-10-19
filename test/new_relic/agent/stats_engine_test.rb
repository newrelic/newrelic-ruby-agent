# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))


class NewRelic::Agent::StatsEngineTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent::StatsEngine.new
  rescue => e
    puts e
    puts e.backtrace.join("\n")
  end

  def teardown
    @engine.harvest
    mocha_teardown
    super
  end

  def test_scope
    @engine.push_scope(:scope1)
    assert_equal 1, @engine.scope_stack.size

    expected = @engine.push_scope(:scope2)
    @engine.pop_scope(expected, "name 2")

    scoped = @engine.get_stats "a"
    scoped.trace_call 3

    assert scoped.total_call_time == 3
    unscoped = @engine.get_stats "a"

    assert scoped == @engine.get_stats("a")
    assert unscoped.total_call_time == 3
  end

  def test_scope__overlap
    NewRelic::Agent.instance.stubs(:stats_engine).returns(@engine)

    freeze_time
    in_transaction('orlando') do
      self.class.trace_execution_scoped('disney', :deduct_call_time_from_parent => false) { advance_time(0.1) }
    end
    orlando_disney = @engine.lookup_stats('disney', 'orlando')

    in_transaction('anaheim') do
      self.class.trace_execution_scoped('disney', :deduct_call_time_from_parent => false) { advance_time(0.11) }
    end
    anaheim_disney = @engine.lookup_stats('disney', 'anaheim')

    disney = @engine.lookup_stats("disney")

    assert_not_same orlando_disney, anaheim_disney
    assert_not_equal orlando_disney, anaheim_disney
    assert_equal 1, orlando_disney.call_count
    assert_equal 1, anaheim_disney.call_count
    assert_equal 2, disney.call_count
    assert_equal disney.total_call_time, orlando_disney.total_call_time + anaheim_disney.total_call_time
  end

  def test_simplethrowcase(depth=0)
    fail "doh" if depth == 10

    scope = @engine.push_scope(:"scope#{depth}")

    begin
      test_simplethrowcase(depth+1)
    rescue StandardError => e
      if (depth != 0)
        raise e
      end
    ensure
      @engine.pop_scope(scope, "name #{depth}")
    end

    if depth == 0
      assert @engine.scope_stack.empty?
    end
  end


  def test_scope_failure
    scope1 = @engine.push_scope(:scope1)
    scope2 = @engine.push_scope(:scope2)
    assert_raises(RuntimeError) do
      @engine.pop_scope(scope1, "name 1")
    end
  end

  def test_children_time
    t1 = freeze_time
    expected1 = @engine.push_scope(:a)
    advance_time(0.001)
    t2 = Time.now

    expected2 = @engine.push_scope(:b)
    advance_time(0.002)
    t3 = Time.now

    expected = @engine.push_scope(:c)
    advance_time(0.003)
    scope = @engine.pop_scope(expected, "metric c")

    t4 = Time.now
    assert_equal 0, scope.children_time

    advance_time(0.001)
    t5 = Time.now

    expected = @engine.push_scope(:d)
    advance_time(0.002)
    scope = @engine.pop_scope(expected, "metric d")

    t6 = Time.now

    assert_equal 0, scope.children_time

    scope = @engine.pop_scope(expected2, "metric b")
    assert_equal 'metric b', scope.name

    assert_in_delta((t4 - t3) + (t6 - t5), scope.children_time, 0.0001)

    scope = @engine.pop_scope(expected1, "metric a")
    assert_equal scope.name, 'metric a'

    assert_in_delta((t6 - t2), scope.children_time, 0.0001)
  end

  def test_simple_start_transaction
    assert @engine.scope_stack.empty?
    scope = @engine.push_scope :tag
    @engine.start_transaction
    assert !@engine.scope_stack.empty?
    @engine.pop_scope(scope, "name")
    assert @engine.scope_stack.empty?
    @engine.end_transaction
    assert @engine.scope_stack.empty?
  end


  # test for when the scope stack contains an element only used for tts and not metrics
  def test_simple_tt_only_scope
    scope1 = @engine.push_scope(:a, 0, true)
    scope2 = @engine.push_scope(:b, 10, false)
    scope3 = @engine.push_scope(:c, 20, true)

    @engine.pop_scope(scope3, "name a", 30)
    @engine.pop_scope(scope2, "name b", 20)
    @engine.pop_scope(scope1, "name c", 10)

    assert_equal 0, scope3.children_time
    assert_equal 10, scope2.children_time
    assert_equal 10, scope1.children_time
  end

  def test_double_tt_only_scope
    scope1 = @engine.push_scope(:a, 0, true)
    scope2 = @engine.push_scope(:b, 10, false)
    scope3 = @engine.push_scope(:c, 20, false)
    scope4 = @engine.push_scope(:d, 30, true)

    @engine.pop_scope(scope4, "name d", 40)
    @engine.pop_scope(scope3, "name c", 30)
    @engine.pop_scope(scope2, "name b", 20)
    @engine.pop_scope(scope1, "name a", 10)

    assert_equal 0, scope4.children_time.round
    assert_equal 10, scope3.children_time.round
    assert_equal 10, scope2.children_time.round
    assert_equal 10, scope1.children_time.round
  end

  def test_sampler_enabling
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => false)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => false, :developer_mode => true)
    assert_sampler_enabled_with(true,  :'transaction_tracer.enabled' => true,  :developer_mode => true)

    assert_sampler_enabled_with(false, :'transaction_tracer.enabled' => false, :developer_mode => false)
  end

  def assert_sampler_enabled_with(expected, opts={})
    with_config(opts) do
      assert_equal expected, @engine.sampler_enabled?
    end
  end
end
