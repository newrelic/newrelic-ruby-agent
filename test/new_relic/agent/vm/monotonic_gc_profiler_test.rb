# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, "..", "..", "..", "..", "test_helper"))
require 'new_relic/agent/vm/monotonic_gc_profiler'

class MonotonicGCProfilerTest < MiniTest::Unit::TestCase
  def test_total_time_isnt_nil
    result = NewRelic::Agent::VM::MonotonicGCProfiler.new.total_time
    refute_nil result
  end
end
