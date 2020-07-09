# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# To use this module to test your aggregator, implement the following
# methods before including it:
#
# generate_event(name, options = {}) # Record an event of the same type that
#                                    # this aggregator uses
#
# last_events()                      # Harvest and return all events
#
# aggregator                         # Instance of the aggregator class under test
#
# name_for(event)                    # Returns the transaction name of the
#                                    # passed-in event
#
# enabled_keys()                      # (optional) config key that gates this aggregator

module NewRelic
  module CommonAggregatorTests
    def enabled_keys
      aggregator.class.enabled_keys
    end

    def test_samples_on_transaction_finished_event
      generate_event
      assert_equal 1, last_events.length
    end

    def test_records_background_tasks
      generate_event('a', :type => :controller)
      generate_event('b', :type => :background)
      assert_equal 2, last_events.size
    end

    def test_can_disable_sampling_for_analytics
      with_container_disabled do
        generate_event
        assert_empty last_events
      end
    end

    def test_harvest_returns_previous_sample_list
      5.times { generate_event }

      _, old_samples = aggregator.harvest!

      assert_equal 5, old_samples.size
      assert_equal 0, last_events.size
    end

    def test_merge_merges_samples_back_into_buffer
      5.times { generate_event }
      old_samples = aggregator.harvest!
      5.times { generate_event }

      aggregator.merge!(old_samples)

      assert_equal(10, last_events.size)
    end

    def test_respects_max_samples_stored
      with_config aggregator.class.capacity_key => 5 do
        10.times { generate_event }
      end

      assert_equal 5, last_events.size
    end

    def test_merge_abides_by_max_samples_limit
      with_config(aggregator.class.capacity_key => 5) do
        4.times { generate_event }
        old_samples = aggregator.harvest!
        4.times { generate_event }

        aggregator.merge!(old_samples)
        assert_equal(5, last_events.size)
      end
    end

    def test_does_not_drop_samples_when_used_from_multiple_threads
      with_config( aggregator.class.capacity_key => 100 * 100 ) do
        threads = []
        25.times do
          threads << Thread.new do
            100.times { generate_event }
          end
        end
        threads.each { |t| t.join }

        assert_equal(25 * 100, last_events.size)
      end
    end

    def test_lower_priority_events_discarded_in_favor_higher_priority_events
      with_config aggregator.class.capacity_key => 5 do
        5.times { |i| generate_event "totally_not_sampled_#{i}", :priority => rand     }
        5.times { |i| generate_event "sampled_#{i}",             :priority => rand + 1 }

        _, events = aggregator.harvest!

        expected = (0..4).map { |i| "sampled_#{i}" }

        assert_equal_unordered expected, events.map { |e| name_for(e) }
      end
    end

    def test_higher_priority_events_not_discarded_in_favor_of_lower_priority_events
      with_config aggregator.class.capacity_key => 5 do
        5.times { |i| generate_event "sampled_#{i}",             :priority => rand + 1 }
        5.times { |i| generate_event "totally_not_sampled_#{i}", :priority => rand     }

        _, events = aggregator.harvest!

        expected = (0..4).map { |i| "sampled_#{i}" }

        assert_equal_unordered expected, events.map { |e| name_for(e) }
      end
    end

    def test_reservoir_stats_reset_after_harvest
      5.times { generate_event }

      reservoir_stats, _ = aggregator.harvest!
      assert_equal 5, reservoir_stats[:events_seen]

      reservoir_stats, _ = aggregator.harvest!
      assert_equal 0, reservoir_stats[:events_seen]
    end

    def test_sample_counts_are_correct_after_merge
      with_config aggregator.class.capacity_key => 5 do
        buffer = aggregator.instance_variable_get :@buffer

        4.times { generate_event }
        last_harvest = aggregator.harvest!

        assert_equal 4, buffer.seen_lifetime
        assert_equal 4, buffer.captured_lifetime
        assert_equal 4, last_harvest[0][:events_seen]

        4.times { generate_event }
        aggregator.merge! last_harvest

        reservoir_stats, samples = aggregator.harvest!

        assert_equal 5, samples.size
        assert_equal 8, reservoir_stats[:events_seen]
        assert_equal 8, buffer.seen_lifetime
        assert_equal 5, buffer.captured_lifetime
      end
    end

    def test_resets_limits_on_harvest
      with_config aggregator.class.capacity_key => 100 do
        50.times { generate_event }
        events_before = last_events
        assert_equal 50, events_before.size

        150.times { generate_event }
        events_after = last_events
        assert_equal 100, events_after.size
      end
    end

    def with_container_disabled &blk
      options = enabled_keys.inject({}) do |memo, opt|
        memo[opt] = false
        memo
      end
      aggregator.class.stubs(:enabled_fn).returns(Proc.new { false })
      with_server_source(options, &blk)
    end
  end
end
