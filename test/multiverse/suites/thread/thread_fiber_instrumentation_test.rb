# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ThreadFiberInstrumentationTest < Minitest::Test
  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def do_segment(name: 'anything', &block)
    segment = NewRelic::Agent::Tracer.start_segment(name: name)
    yield(segment)
    segment.finish
  end

  def assert_parent(parent, child)
    assert_equal parent.guid, child.parent.guid
  end

  def run_or_wait(async)
    if async.class == Thread
      async.join
    elsif async.class == Fiber
      async.resume
    end
  end

  def run_nested_parent_test(async_class1, async_class2 = nil)
    async_class2 ||= async_class1

    in_transaction do |txn|
      do_segment(name: 'Outer') do |outer_segment|
        async1 = async_class1.new do
          fiber_segment = NewRelic::Agent::Tracer.current_segment

          assert_parent outer_segment, fiber_segment
          async2 = nil
          do_segment(name: 'Inner') do |inner_segment|
            assert_parent fiber_segment, inner_segment
            async2 = async_class2.new do
              assert_parent inner_segment, NewRelic::Agent::Tracer.current_segment
            end
          end

          do_segment(name: 'Inner2') do |inner_2_segment|
            assert_parent fiber_segment, inner_2_segment
          end
          run_or_wait(async2)
        end
        run_or_wait(async1)
      end
    end

    assert_equal 6, harvest_span_events![0][:events_seen]
  end

  def test_parents_thread_thread
    run_nested_parent_test(Thread)
  end

  def test_parents_fiber_fiber
    run_nested_parent_test(Fiber)
  end

  def test_parents_thread_fiber
    run_nested_parent_test(Thread, Fiber)
  end

  def test_parents_fiber_thread
    run_nested_parent_test(Fiber, Thread)
  end
end
