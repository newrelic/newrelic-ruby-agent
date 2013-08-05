# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/threading/backtrace_node'

module NewRelic::Agent::Threading
  class BacktraceNodeTest < Test::Unit::TestCase
    SINGLE_LINE = "irb.rb:69:in `catch'"

    def test_single_node_converts_to_array
      line = "irb.rb:69:in `catch'"
      node = BacktraceNode.new(line)

      assert_equal([
                   ["irb.rb", "catch", 69],
                   0, 0,
                   []],
                   node.to_array)
    end

    def test_multiple_nodes_converts_to_array
      line = "irb.rb:69:in `catch'"
      child_line = "bacon.rb:42:in `yum'"
      node = BacktraceNode.new(line)
      child = BacktraceNode.new(child_line, node)

      assert_equal([
                   ["irb.rb", "catch", 69],
                   0, 0,
                   [
                     [
                       ['bacon.rb', 'yum', 42],
                       0,0,
                       []
      ]
      ]],
        node.to_array)
    end

    def test_gracefully_handle_bad_values_in_to_array
      node = BacktraceNode.new(SINGLE_LINE)
      node.instance_variable_set(:@line_no, "blarg")
      node.runnable_count = Rational(10, 1)

      assert_equal([
                   ["irb.rb", "catch", 0],
                   10, 0,
                   []],
                   node.to_array)
    end

    def test_add_child_twice
      parent = BacktraceNode.new(SINGLE_LINE)
      child = BacktraceNode.new(SINGLE_LINE)

      parent.add_child(child)
      parent.add_child(child)

      assert_equal 1, parent.children.size
    end

    def test_prune_keeps_children
      parent = BacktraceNode.new(SINGLE_LINE)
      child = BacktraceNode.new(SINGLE_LINE, parent)

      parent.prune!

      assert_equal [child], parent.children
    end

    def test_prune_removes_children
      parent = BacktraceNode.new(SINGLE_LINE)
      child = BacktraceNode.new(SINGLE_LINE, parent)

      child.to_prune = true
      parent.prune!

      assert_equal [], parent.children
    end

    def test_prune_removes_grandchildren
      parent = BacktraceNode.new(SINGLE_LINE)
      child = BacktraceNode.new(SINGLE_LINE, parent)
      grandchild = BacktraceNode.new(SINGLE_LINE, child)

      grandchild.to_prune = true
      parent.prune!

      assert_equal [child], parent.children
      assert_equal [], child.children
    end

  end
end
