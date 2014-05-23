# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, "..", "..", "..", "..", "test_helper"))
require 'new_relic/agent/vm/rubinius_vm'

if NewRelic::LanguageSupport.rubinius?
  class NewRelic::Agent::VM::RubiniusVMTest < Minitest::Test
    def test_normal_usage
      with_stats({ :gc => {
        :full  => { :count => 1 },
        :young => { :count => 2 }
      }})

      has_major_minor(1, 2)
    end

    def test_missing_full
      with_stats({ :gc => {
        :young => { :count => 2 }
      }})

      has_major_minor(nil, 2)
    end

    def test_missing_full_count
      with_stats({ :gc => {
        :full  => { },
        :young => { :count => 2 }
      }})

      has_major_minor(nil, 2)
    end

    def test_missing_young
      with_stats({ :gc => {
        :full => { :count => 1 }
      }})

      has_major_minor(1, nil)
    end

    def test_missing_young_count
      with_stats({ :gc => {
        :full  => { :count => 1},
        :young => { }
      }})

      has_major_minor(1, nil)
    end

    def test_missing_gc
      with_stats({})
      has_major_minor(nil, nil)
    end

    def with_stats(stats)
      GC.stubs(:stat).returns(stats)
    end

    def has_major_minor(major, minor)
      snapshot = NewRelic::Agent::VM::RubiniusVM.new.snapshot
      assert_equal(major, snapshot.major_gc_count)
      assert_equal(minor, snapshot.minor_gc_count)
    end
  end
end
