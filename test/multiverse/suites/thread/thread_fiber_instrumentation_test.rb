# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'async'

class ThreadFiberInstrumentationTest < Minitest::Test
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

  def test_parents_fibers_nested_in_fibers
    tasks = []

    in_transaction do |txn|
      do_segment(name: 'Outer') do |outer_segment|
        fiber1 = Fiber.new do
          fiber_segment = NewRelic::Agent::Tracer.current_segment

          assert_parent outer_segment, fiber_segment
          fiber2 = nil
          do_segment(name: 'Inner') do |inner_segment|
            assert_parent fiber_segment, inner_segment
            fiber2 = Fiber.new do
              assert_parent inner_segment, NewRelic::Agent::Tracer.current_segment
            end
          end

          do_segment(name: 'Inner2') do |inner_2_segment|
            assert_parent fiber_segment, inner_2_segment
          end
          fiber2.resume
        end
        fiber1.resume
      end
    end

    assert_equal 6, harvest_span_events![0][:events_seen]
  end
end
