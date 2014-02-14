# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampler'
require 'new_relic/agent/vm'

module NewRelic
  module Agent
    module Samplers
      class VMSampler < Sampler
        attr_reader :transaction_count

        def initialize
          super :vm
          @lock = Mutex.new
          @transaction_count = 0
          @last_snapshot = take_snapshot
        end

        def take_snapshot
          NewRelic::Agent::VM.snapshot
        end

        def setup_events(event_listener)
          event_listener.subscribe(:transaction_finished, &method(:on_transaction_finished))
        end

        def on_transaction_finished(*_)
          @lock.synchronize { @transaction_count += 1 }
        end

        def reset_transaction_count
          @lock.synchronize do
            old_count = @transaction_count
            @transaction_count = 0
            old_count
          end
        end

        def record_gc_runs_metric(snapshot, txn_count)
          if snapshot.gc_total_time || snapshot.gc_runs
            if snapshot.gc_total_time
              gc_time = snapshot.gc_total_time - @last_snapshot.gc_total_time
            end
            if snapshot.gc_runs
              gc_runs = snapshot.gc_runs - @last_snapshot.gc_runs
            end
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/GC/runs') do |stats|
              stats.call_count           = txn_count
              stats.total_call_time      = gc_runs if gc_runs
              stats.total_exclusive_time = gc_time if gc_time
            end
          end
        end

        def record_object_allocations_metric(snapshot, txn_count)
          if snapshot.total_allocated_object
            delta = snapshot.total_allocated_object - @last_snapshot.total_allocated_object
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/GC/total_allocated_object') do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def record_major_gc_count(snapshot, txn_count)
          if snapshot.major_gc_count
            delta = snapshot.major_gc_count - @last_snapshot.major_gc_count
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/GC/major_gc_count') do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def record_minor_gc_count(snapshot, txn_count)
          if snapshot.minor_gc_count
            delta = snapshot.minor_gc_count - @last_snapshot.minor_gc_count
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/GC/minor_gc_count') do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def record_heap_live_metric(snapshot)
          if snapshot.heap_live
            NewRelic::Agent.record_metric('RubyVM/GC/heap_live', :count => snapshot.heap_live)
          end
        end

        def record_heap_free_metric(snapshot)
          if snapshot.heap_free
            NewRelic::Agent.record_metric('RubyVM/GC/heap_free', :count => snapshot.heap_free)
          end
        end

        def record_method_cache_invalidations(snapshot, txn_count)
          if snapshot.method_cache_invalidations
            delta = snapshot.method_cache_invalidations - @last_snapshot.method_cache_invalidations
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/CacheInvalidations/method') do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def record_constant_cache_invalidations(snapshot, txn_count)
          if snapshot.constant_cache_invalidations
            delta = snapshot.constant_cache_invalidations - @last_snapshot.constant_cache_invalidations
            NewRelic::Agent.agent.stats_engine.record_metrics('RubyVM/CacheInvalidations/constant') do |stats|
              stats.call_count      = txn_count
              stats.total_call_time = delta
            end
          end
        end

        def poll
          snapshot = take_snapshot
          txn_count = reset_transaction_count

          record_gc_runs_metric(snapshot, txn_count)
          record_object_allocations_metric(snapshot, txn_count)
          record_major_gc_count(snapshot, txn_count)
          record_minor_gc_count(snapshot, txn_count)
          record_method_cache_invalidations(snapshot, txn_count)
          record_constant_cache_invalidations(snapshot, txn_count)
          record_heap_live_metric(snapshot)
          record_heap_free_metric(snapshot)
          NewRelic::Agent.record_metric('RubyVM/Threads/all', :count => snapshot.thread_count)

          @last_snapshot = snapshot
        end
      end
    end
  end
end
