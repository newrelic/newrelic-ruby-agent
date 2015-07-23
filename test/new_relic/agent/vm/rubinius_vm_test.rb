# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, "..", "..", "..", "..", "test_helper"))
require 'new_relic/agent/vm/rubinius_vm'

if NewRelic::LanguageSupport.rubinius?
  class NewRelic::Agent::VM::RubiniusVMTest < Minitest::Test
    def setup
      @snap = NewRelic::Agent::VM::Snapshot.new
      @vm = NewRelic::Agent::VM::RubiniusVM.new
    end

    def test_gc_runs
      @vm.gather_gc_stats(@snap)

      refute_nil @snap.gc_runs
    end

    def test_gather_stats_from_metrics_sets_major_gc_count
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.major_gc_count
    end

    def test_gather_stats_from_metrics_sets_minor_gc_count
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.minor_gc_count
    end

    def test_gather_stats_from_metrics_sets_major_gc_count
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.major_gc_count
    end

    def test_gather_stats_from_metrics_sets_heap_live_slots
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.heap_live
    end

    def test_gather_stats_from_metrics_sets_total_allocated_objects
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.total_allocated_object if @vm.supports?(:total_allocated_object)
    end

    def test_gather_stats_from_metrics_sets_method_cache_invalidations
      @vm.gather_stats_from_metrics(@snap)

      refute_nil @snap.method_cache_invalidations
    end

    def test_gather_gc_time
      @vm.gather_gc_time(@snap)

      refute_nil @snap.gc_total_time
    end

    def test_gather_tread_stats
      @vm.gather_thread_stats(@snap)

      refute_nil @snap.thread_count
    end
  end
end
