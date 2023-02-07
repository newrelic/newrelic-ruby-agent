# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'async'

class FiberInstrumentationTest < Minitest::Test
  def setup
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  # Add tests here

  # Fiber > fiber
  # Fiber > thread
  # Thread > fiber
  # Thread > Thread

  def do_segment(name: 'anything', &block)
    segment = NewRelic::Agent::Tracer.start_segment(name: name)
    yield(segment)
    segment.finish
  end

  def assert_parent(parent, child)
    assert_equal parent.guid, child.parent.guid
  end

  def test_parents_nested_in_fibers
    tasks = []

    in_transaction do |txn|
      do_segment(name: 'Outer') do |outer_segment|
        tasks << Async do |task|
          fiber_segment = NewRelic::Agent::Tracer.current_segment

          assert_parent outer_segment, fiber_segment
          do_segment(name: 'Inner') do |inner_segment|
            assert_parent fiber_segment, inner_segment
            task.async do
              assert_parent inner_segment, NewRelic::Agent::Tracer.current_segment
            end
          end
        end
      end

      tasks.each(&:wait)
    end

    assert_equal 5, harvest_span_events![0][:events_seen]
  end
end
