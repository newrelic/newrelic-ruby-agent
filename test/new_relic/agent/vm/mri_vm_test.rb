# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/vm/mri_vm'

unless NewRelic::LanguageSupport.jruby?
  module NewRelic
    module Agent
      module VM
        class MriVMTest < Minitest::Test
          def setup
            @snap = Snapshot.new
            @vm = MriVM.new
          end

          def test_gather_gc_time_sets_gc_total_time_if_gc_profiler_is_enabled
            NewRelic::LanguageSupport.stubs(:gc_profiler_enabled?).returns(true)
            @vm.gather_gc_time(@snap)
            refute_nil @snap.gc_total_time
          end

          def test_gather_gc_time_does_not_set_gc_total_time_if_gc_profiler_is_disabled
            NewRelic::LanguageSupport.stubs(:gc_profiler_enabled?).returns(false)
            @vm.gather_gc_time(@snap)
            assert_nil @snap.gc_total_time
          end

          def test_gather_stats_records_gc_time_if_available
            NewRelic::Agent.instance.monotonic_gc_profiler.stubs(:total_time_s).returns(999)
            NewRelic::LanguageSupport.stubs(:gc_profiler_enabled?).returns(true)
            @vm.gather_stats(@snap)
            assert_equal(999, @snap.gc_total_time)
          end
        end
      end
    end
  end
end
