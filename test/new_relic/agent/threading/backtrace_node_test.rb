# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/threading/backtrace_node'

module NewRelic::Agent::Threading
  class BacktraceNodeTest < Test::Unit::TestCase
    SINGLE_LINE = "irb.rb:69:in `catch'"

    def setup
      @node = BacktraceNode.new(nil)
      @single_trace = [
        "irb.rb:69:in `catch'",
        "irb.rb:69:in `start'",
        "irb:12:in `<main>'"
      ]
    end

    def assert_backtrace_trees_equal(a, b, original_a=a, original_b=b)
      message = "Thread profiles did not match.\n\n"
      message << "Expected tree:\n#{original_a.dump_string}\n\n"
      message << "Actual tree:\n#{original_b.dump_string}\n"
      assert_equal(a, b, message)
      assert_equal(a.children, b.children, message)
      a.children.zip(b.children) do |a_child, b_child|
        assert_backtrace_trees_equal(a_child, b_child, a, b)
      end
    end

    def create_node(frame, parent=nil, runnable_count=0)
      node = BacktraceNode.new(frame)
      parent.add_child_unless_present(node) if parent
      node.runnable_count = runnable_count
      node
    end

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
      node = create_node(line)
      create_node(child_line, node)

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
      node.stubs(:parse_backtrace_frame).returns(["irb.rb", "catch", "blarg"])
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

      parent.add_child_unless_present(child)
      parent.add_child_unless_present(child)

      assert_equal 1, parent.children.size
    end

    def test_prune_keeps_children
      parent = create_node(SINGLE_LINE)
      child = create_node(SINGLE_LINE, parent)

      parent.prune!([])

      assert_equal [child], parent.children
    end

    def test_prune_removes_children
      parent = create_node(SINGLE_LINE)
      child = create_node(SINGLE_LINE, parent)

      parent.prune!([child])

      assert_equal [], parent.children
    end

    def test_prune_removes_grandchildren
      parent = create_node(SINGLE_LINE)
      child = create_node(SINGLE_LINE, parent)
      grandchild = create_node(SINGLE_LINE, child)

      parent.prune!([grandchild])

      assert_equal [child], parent.children
      assert_equal [], child.children
    end

    def test_aggregate_empty_trace
      @node.aggregate([])
      assert @node.empty?
    end

    def test_aggregate_builds_tree_from_first_trace
      @node.aggregate(@single_trace)

      root = BacktraceNode.new(nil)
      tree = create_node(@single_trace[-1], root, 1)
      child = create_node(@single_trace[-2], tree, 1)
      create_node(@single_trace[-3], child, 1)

      assert_backtrace_trees_equal root, @node
    end

    def test_aggregate_builds_tree_from_overlapping_traces
      @node.aggregate(@single_trace)
      @node.aggregate(@single_trace)

      root = BacktraceNode.new(nil)
      tree = create_node(@single_trace[-1], root, 2)
      child = create_node(@single_trace[-2], tree, 2)
      create_node(@single_trace[-3], child, 2)

      assert_backtrace_trees_equal root, @node
    end

    def test_aggregate_builds_tree_from_diverging_traces
      backtrace1 = [
        "baz.rb:3:in `baz'",
        "bar.rb:2:in `bar'",
        "foo.rb:1:in `foo'"
      ]

      backtrace2 = [
        "wiggle.rb:3:in `wiggle'",
        "qux.rb:2:in `qux'",
        "foo.rb:1:in `foo'"
      ]

      @node.aggregate(backtrace1)
      @node.aggregate(backtrace2)

      root = BacktraceNode.new(nil)

      tree = create_node(backtrace1.last, root, 2)

      bar_node = create_node(backtrace1[1], tree, 1)
      create_node(backtrace1[0], bar_node, 1)

      qux_node = create_node(backtrace2[1], tree, 1)
      create_node(backtrace2[0], qux_node, 1)

      assert_backtrace_trees_equal(root, @node)
    end

    def test_aggregate_doesnt_create_duplicate_children
      @node.aggregate(@single_trace)
      @node.aggregate(@single_trace)

      root = BacktraceNode.new(nil)
      tree = create_node(@single_trace[-1], root, 2)
      child = create_node(@single_trace[-2], tree, 2)
      create_node(@single_trace[-3], child, 2)

      assert_backtrace_trees_equal(root, @node)
    end 
  end
end
