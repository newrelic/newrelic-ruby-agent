# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, "..", "..", "..", "..", "test_helper"))
require 'new_relic/agent/vm/monotonic_gc_profiler'

class MonotonicGCProfilerTest < MiniTest::Unit::TestCase
  attr_reader :profiler

  def setup
    @profiler = NewRelic::Agent::VM::MonotonicGCProfiler.new
  end

  def test_total_time_isnt_nil
    refute_nil profiler.total_time
  end

  def test_total_time_reads_from_gc_profiler
    GC::Profiler.stubs(:total_time).returns(0)
    assert_equal 0, profiler.total_time

    GC::Profiler.stubs(:total_time).returns(100)
    assert_equal 100, profiler.total_time
  end

  def test_total_time_resets_underlying_gc_profiler
    GC::Profiler.expects(:clear).once
    profiler.total_time
  end
end
