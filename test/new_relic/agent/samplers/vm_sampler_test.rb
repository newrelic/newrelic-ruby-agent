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
            :gc_runs                => 0,
            :gc_total_time          => 0,
            :total_allocated_object => 0,
            :major_gc_count         => 0,
            :minor_gc_count         => 0,
            :heap_live              => 0,
            :heap_free              => 0
          )
          @sampler = VMSampler.new
          @sampler.setup_events(NewRelic::Agent.instance.events)
        end

        def test_supported_on_this_platform?
          assert VMSampler.supported_on_this_platform?
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
          expected = { 'RubyVM/Threads/all' => { :call_count => 2 } }
          assert_metrics_recorded(expected)
        end

        def test_poll_records_gc_runs_metric
          stub_snapshot(:gc_runs => 10, :gc_total_time => 100)
          generate_transactions(50)
          @sampler.poll

          assert_metrics_recorded(
            'RubyVM/GC/runs' => {
              :call_count           => 50, # number of transactions
              :total_call_time      => 10, # number of GC runs
              :total_exclusive_time => 100 # total GC time
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
            'RubyVM/GC/heap_live' => { :call_count => 100 },
            'RubyVM/GC/heap_free' => { :call_count => 25  }
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
