# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/samplers/vm_sampler'
require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module Samplers
      class VMSamplerTest < Minitest::Test
        def setup
          stub_snapshot(
            :taken_at                     => 0,
            :gc_runs                      => 0,
            :gc_total_time                => 0,
            :total_allocated_object       => 0,
            :major_gc_count               => 0,
            :minor_gc_count               => 0,
            :heap_live                    => 0,
            :heap_free                    => 0,
            :method_cache_invalidations   => 0,
            :constant_cache_invalidations => 0
          )
          @sampler = VMSampler.new
          @sampler.setup_events(NewRelic::Agent.instance.events)
          NewRelic::Agent.drop_buffered_data
        end

        def test_supported_on_this_platform?
          assert VMSampler.supported_on_this_platform?
        end

        def test_enabled_should_return_false_if_disabled_via_config_setting
          with_config(:disable_vm_sampler => true) do
            refute VMSampler.enabled?
          end
        end

        def test_records_transaction_count
          generate_transactions(10)
          assert_equal(10, @sampler.transaction_count)
        end

        def test_reset_transaction_count
          generate_transactions(10)

          old_count = @sampler.reset_transaction_count
          assert_equal(10, old_count)
          assert_equal(0, @sampler.transaction_count)
        end

        def test_poll_records_thread_count
          stub_snapshot(:thread_count => 2)

          @sampler.poll
          assert_metrics_recorded(
            'RubyVM/Threads/all' => {
              :call_count => 2,
              :sum_of_squares => 1
            }
          )
        end

        def test_poll_records_gc_runs_metric
          stub_snapshot(:gc_runs => 10, :gc_total_time => 100, :taken_at => 200)
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :call_count           => 50,  # number of transactions
              :total_call_time      => 10,  # number of GC runs
              :total_exclusive_time => 100, # total GC time
              :sum_of_squares       => 200  # total wall clock time
            }
          )
        end

        def test_poll_records_total_allocated_object
          stub_snapshot(:total_allocated_object => 25)
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/total_allocated_object' => {
              :call_count      => 50, # number of transactions
              :total_call_time => 25  # number of allocated objects
            }
          )
        end

        def test_poll_records_major_minor_gc_counts
          stub_snapshot(:major_gc_count => 10, :minor_gc_count => 20)
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/major_gc_count' => {
              :call_count      => 50, # number of transactions
              :total_call_time => 10  # number of major GC runs
            },
            'RubyVM/GC/minor_gc_count' => {
              :call_count      => 50, # number of transactions
              :total_call_time => 20  # number of minor GC runs
            }
          )
        end

        def test_poll_records_heap_usage_metrics
          stub_snapshot(:heap_live => 100, :heap_free => 25)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/heap_live' => {
              :call_count     => 100,
              :sum_of_squares => 1
            },
            'RubyVM/GC/heap_free' => {
              :call_count      => 25,
              :sum_of_squares  => 1
            }
          )
        end

        def test_poll_records_vm_cache_invalidations
          stub_snapshot(
            :method_cache_invalidations   => 100,
            :constant_cache_invalidations => 200
          )
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/CacheInvalidations/method' => {
              :call_count      => 50, # number of transactions
              :total_call_time => 100 # number of method cache invalidations
            },
            'RubyVM/CacheInvalidations/constant' => {
              :call_count      => 50, # number of transactions
              :total_call_time => 200 # number of constant cache invalidations
            }
          )
        end

        def test_poll_gracefully_handles_missing_fields
          stub_snapshot({}) # snapshot will be empty
          @sampler.poll

          assert_metrics_not_recorded([
            'RubyVM/GC/runs',
            'RubyVM/GC/total_allocated_object',
            'RubyVM/GC/major_gc_count',
            'RubyVM/GC/minor_gc_count',
            'RubyVM/GC/heap_live',
            'RubyVM/GC/heap_free',
            'RubyVM/CacheInvalidations/method',
            'RubyVM/CacheInvalidations/constant'
          ])
        end

        def test_poll_handles_missing_gc_time_but_present_gc_count
          # We were able to determine the number of GC runs, but not the total
          # GC time. This will be the case if GC::Profiler is not available.
          stub_snapshot(:gc_runs => 10, :taken_at => 60)
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :call_count           => 50, # number of transactions
              :total_call_time      => 10, # number of GC runs
              :total_exclusive_time => 0,  # total GC time
              :sum_of_squares       => 60  # total wall clock time
            }
          )
        end

        def test_poll_records_deltas_not_cumulative_values
          stub_snapshot(
            :gc_runs                      => 10,
            :gc_total_time                => 10,
            :total_allocated_object       => 10,
            :major_gc_count               => 10,
            :minor_gc_count               => 10,
            :method_cache_invalidations   => 10,
            :constant_cache_invalidations => 10
          )
          @sampler.poll

          expected = {
            'RubyVM/GC/runs' => {
              :total_call_time      => 10,
              :total_exclusive_time => 10
            },
            'RubyVM/GC/total_allocated_object' => {
              :total_call_time => 10
            },
            'RubyVM/GC/major_gc_count' => {
              :total_call_time => 10
            },
            'RubyVM/GC/minor_gc_count' => {
              :total_call_time => 10
            },
            'RubyVM/CacheInvalidations/method' => {
              :total_call_time => 10
            },
            'RubyVM/CacheInvalidations/constant' => {
              :total_call_time => 10
            }
          }

          assert_metrics_recorded(expected)

          NewRelic::Agent.drop_buffered_data

          stub_snapshot(
            :gc_runs                      => 20,
            :gc_total_time                => 20,
            :total_allocated_object       => 20,
            :major_gc_count               => 20,
            :minor_gc_count               => 20,
            :method_cache_invalidations   => 20,
            :constant_cache_invalidations => 20
          )
          @sampler.poll

          assert_metrics_recorded(expected)
        end

        # This test simulates multiple poll cycles without a metric reset
        # between them. This can happen, for example, when the agent fails to
        # post metric data to the collector.
        def test_poll_aggregates_multiple_polls
          stub_snapshot(
            :gc_runs                      => 10,
            :gc_total_time                => 10,
            :total_allocated_object       => 10,
            :major_gc_count               => 10,
            :minor_gc_count               => 10,
            :method_cache_invalidations   => 10,
            :constant_cache_invalidations => 10,
            :taken_at                     => 10
          )
          generate_transactions(10)
          @sampler.poll

          stub_snapshot(
            :gc_runs                      => 20,
            :gc_total_time                => 20,
            :total_allocated_object       => 20,
            :major_gc_count               => 20,
            :minor_gc_count               => 20,
            :method_cache_invalidations   => 20,
            :constant_cache_invalidations => 20,
            :taken_at                     => 20
          )
          generate_transactions(10)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :call_count           => 20,
              :total_call_time      => 20,
              :total_exclusive_time => 20,
              :sum_of_squares       => 20
            },
            'RubyVM/GC/total_allocated_object' => {
              :call_count      => 20,
              :total_call_time => 20
            },
            'RubyVM/GC/major_gc_count' => {
              :call_count      => 20,
              :total_call_time => 20
            },
            'RubyVM/GC/minor_gc_count' => {
              :call_count      => 20,
              :total_call_time => 20
            },
            'RubyVM/CacheInvalidations/method' => {
              :call_count      => 20,
              :total_call_time => 20
            },
            'RubyVM/CacheInvalidations/constant' => {
              :call_count      => 20,
              :total_call_time => 20
            }
          )
        end

        def test_poll_records_wall_clock_time_for_gc_runs_metric
          stub_snapshot(:gc_runs => 10, :gc_total_time => 10, :taken_at => 60)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :total_exclusive_time => 10, # total GC time
              :sum_of_squares       => 60  # total wall clock time
            }
          )

          stub_snapshot(:gc_runs => 10, :gc_total_time => 15, :taken_at => 120)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :total_exclusive_time => 15, # total GC time
              :sum_of_squares       => 120 # total wall clock time
            }
          )
        end

        def test_poll_records_one_in_gc_runs_max_if_gc_time_available
          stub_snapshot(:gc_runs => 10, :gc_total_time => 10)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => { :max_call_time => 1 }
          )
        end

        def test_poll_records_zero_in_gc_runs_max_if_gc_time_not_available
          stub_snapshot(:gc_runs => 10)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => { :max_call_time => 0 }
          )
        end

        def generate_transactions(n)
          n.times do
            in_transaction('txn') { }
          end
        end

        def stub_snapshot(values)
          fakeshot = NewRelic::Agent::VM::Snapshot.new
          values.each do |key, value|
            fakeshot.send("#{key}=", value)
          end
          NewRelic::Agent::VM.stubs(:snapshot).returns(fakeshot)
          fakeshot
        end
      end
    end
  end
end
