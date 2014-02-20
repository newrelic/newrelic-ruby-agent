# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/vm'

class NewRelic::Agent::VMTestCase < Minitest::Test
  attr_reader :vm, :snapshot

  def setup
    @vm = NewRelic::Agent::VM.vm
    @snapshot = NewRelic::Agent::VM.snapshot
  end

  def test_gets_snapshot
    refute_nil snapshot
  end

  EXPECTED_SNAPSHOT_VALUES = [
    :gc_runs,
    :total_allocated_object,
    :major_gc_count,
    :minor_gc_count,
    :heap_live,
    :heap_free,
    :method_cache_invalidations,
    :constant_cache_invalidations,
    :thread_count
  ]

  EXPECTED_SNAPSHOT_VALUES.each do |val|
    define_method("test_snapshot_has_#{val}") do
      assert_correct_value_for(val)
    end
  end

  # A VM snapshot will either support a value and have something non-nil,
  # or it will not support it in which case the method exists but must be nil!
  def assert_correct_value_for(meth)
    if vm.supports?(meth)
      refute_nil snapshot.send(meth)
    else
      assert_nil snapshot.send(meth)
    end
  end
end

