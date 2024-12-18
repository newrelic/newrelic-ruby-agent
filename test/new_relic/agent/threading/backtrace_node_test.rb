# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/threading/backtrace_node'

module NewRelic::Agent::Threading
  class BacktraceNodeTest < Minitest::Test
    def setup
      @single_line = ruby_3_4_0_or_above? ? "irb.rb:69:in 'Kernel#catch'" : "irb.rb:69:in `catch'"
      @node = BacktraceRoot.new
      @single_trace = if ruby_3_4_0_or_above?
        [
          "irb.rb:69:in 'Kernel#catch'",
          "irb.rb:69:in 'Object#start'",
          "irb:12:in '<main>'"
        ]
      else
        [
          "irb.rb:69:in `catch'",
          "irb.rb:69:in `start'",
          "irb:12:in `<main>'"
        ]
      end
    end

    def assert_backtrace_trees_equal(a, b, original_a = a, original_b = b)
      message = +"Thread profiles did not match.\n\n"
      message << "Expected tree:\n#{original_a.dump_string}\n\n"
      message << "Actual tree:\n#{original_b.dump_string}\n"

      assert_equal(a, b, message)
      assert_equal(a.children, b.children, message)
      a.children.zip(b.children) do |a_child, b_child|
        assert_backtrace_trees_equal(a_child, b_child, a, b)
      end
    end

    def create_node(frame, parent = nil, runnable_count = 0)
      node = BacktraceNode.new(frame)
      parent&.add_child_unless_present(node)
      node.runnable_count = runnable_count
      node
    end

    def convert_nodes_to_array(nodes)
      nodes.each { |n| n.mark_for_array_conversion }
      nodes.each { |n| n.complete_array_conversion }
    end

    def test_single_node_converts_to_array
      line = ruby_3_4_0_or_above? ? "irb.rb:69:in 'Kernel#catch'" : "irb.rb:69:in `catch'"
      node = BacktraceNode.new(line)
      convert_nodes_to_array([node])

      expected = if ruby_3_4_0_or_above?
        ['irb.rb', 'Kernel#catch', 69]
      else
        ['irb.rb', 'catch', 69]
      end

      assert_equal([
        expected,
        0, 0,
        []
      ],
        node.as_array)
    end

    def test_multiple_nodes_converts_to_array
      line = ruby_3_4_0_or_above? ? "irb.rb:69:in 'Kernel#catch'" : "irb.rb:69:in `catch'"
      child_line = ruby_3_4_0_or_above? ? "bacon.rb:42:in 'Bacon#yum'" : "bacon.rb:42:in `yum'"
      node = create_node(line)
      child_node = create_node(child_line, node)
      convert_nodes_to_array([node, child_node])

      expected_1 = if ruby_3_4_0_or_above?
        ['irb.rb', 'Kernel#catch', 69]
      else
        ['irb.rb', 'catch', 69]
      end

      expected_2 = if ruby_3_4_0_or_above?
        ['bacon.rb', 'Bacon#yum', 42]
      else
        ['bacon.rb', 'yum', 42]
      end

      assert_equal([
        expected_1,
        0, 0,
        [
          [
            expected_2,
            0, 0,
            []
          ]
        ]
      ],
        node.as_array)
    end

    def test_nodes_in_ruby_3_4_work_with_class_methods
    end

    def test_nodes_without_line_numbers
      line = ruby_3_4_0_or_above? ? "transaction_sample_buffer.rb:in 'TransactionSampleBuffer#visit_node'" : "transaction_sample_buffer.rb:in `visit_node'"
      node = create_node(line)
      convert_nodes_to_array([node])

      expected = if ruby_3_4_0_or_above?
        ['transaction_sample_buffer.rb', 'TransactionSampleBuffer#visit_node', -1]
      else
        ['transaction_sample_buffer.rb', 'visit_node', -1]
      end

      assert_equal([
        expected,
        0, 0,
        []
      ],
        node.as_array)
    end

    def test_gracefully_handle_bad_values_in_to_array
      node = BacktraceNode.new(@single_line)
      node.stubs(:parse_backtrace_frame).returns(['irb.rb', 'catch', 'blarg'])
      node.runnable_count = Rational(10, 1)
      convert_nodes_to_array([node])

      assert_equal([
        ['irb.rb', 'catch', 0],
        10, 0,
        []
      ],
        node.as_array)
    end

    def test_add_child_twice
      parent = BacktraceNode.new(@single_line)
      child = BacktraceNode.new(@single_line)

      parent.add_child_unless_present(child)
      parent.add_child_unless_present(child)

      assert_equal 1, parent.children.size
    end

    def test_aggregate_builds_tree_from_first_trace
      @node.aggregate(@single_trace)

      root = BacktraceRoot.new
      tree = create_node(@single_trace[-1], root, 1)
      child = create_node(@single_trace[-2], tree, 1)
      create_node(@single_trace[-3], child, 1)

      assert_backtrace_trees_equal root, @node
    end

    def test_aggregate_builds_tree_from_overlapping_traces
      @node.aggregate(@single_trace)
      @node.aggregate(@single_trace)

      root = BacktraceRoot.new
      tree = create_node(@single_trace[-1], root, 2)
      child = create_node(@single_trace[-2], tree, 2)
      create_node(@single_trace[-3], child, 2)

      assert_backtrace_trees_equal root, @node
    end

    def test_aggregate_builds_tree_from_diverging_traces
      backtrace1 = if ruby_3_4_0_or_above?
        [
          "baz.rb:3:in 'Object#baz'",
          "bar.rb:2:in 'Object#bar'",
          "foo.rb:1:in 'Object#foo'"
        ]
      else
        [
          "baz.rb:3:in `baz'",
          "bar.rb:2:in `bar'",
          "foo.rb:1:in `foo'"
        ]
      end

      backtrace2 = if ruby_3_4_0_or_above?
        [
          "wiggle.rb:3:in 'Object#wiggle'",
          "qux.rb:2:in 'Object#qux'",
          "foo.rb:1:in 'Object#foo'"
        ]
      else
        [
          "wiggle.rb:3:in `wiggle'",
          "qux.rb:2:in `qux'",
          "foo.rb:1:in `foo'"
        ]
      end

      @node.aggregate(backtrace1)
      @node.aggregate(backtrace2)

      root = BacktraceRoot.new

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

      root = BacktraceRoot.new
      tree = create_node(@single_trace[-1], root, 2)
      child = create_node(@single_trace[-2], tree, 2)
      create_node(@single_trace[-3], child, 2)

      assert_backtrace_trees_equal(root, @node)
    end

    def test_aggregate_limits_recorded_depth
      deep_backtrace = (0..2000).to_a.map { |i| ruby_3_4_0_or_above? ? "foo.rb:#{i}:in 'Foo#foo'" : "foo.rb:#{i}:in `foo'" }

      root = BacktraceRoot.new
      root.aggregate(deep_backtrace)

      assert_equal(MAX_THREAD_PROFILE_DEPTH, root.flattened.size)
    end

    private

    def ruby_3_4_0_or_above?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4.0')
    end
  end
end
