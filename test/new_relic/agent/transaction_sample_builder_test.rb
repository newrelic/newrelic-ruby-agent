# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransactionSampleBuilderTest < Minitest::Test

  def setup
    freeze_time
    @builder = NewRelic::Agent::TransactionSampleBuilder.new
  end

  def test_build_sample
    build_node("a") do
      build_node("aa") do
        build_node("aaa")
      end
      build_node("ab") do
        build_node("aba") do
          build_node("abaa")
        end
        build_node("aba")
        build_node("abc") do
          build_node("abca")
          build_node("abcd")
        end
      end
    end
    build_node "b"
    build_node "c" do
      build_node "ca"
      build_node "cb" do
        build_node "cba"
      end
    end

    @builder.finish_trace(Time.now.to_f)
    validate_builder
  end

  def test_freeze
    build_node "a" do
      build_node "aa"
    end

    @builder.finish_trace(Time.now.to_f)

    validate_builder

    assert_raises(NewRelic::Agent::Transaction::Trace::FinishedTraceError) do
      build_node "b"
    end
  end

  def test_marshal
    build_node "a" do
      build_node "ab"
    end
    build_node "b" do
      build_node "ba"
      build_node "bb"
      build_node "bc" do
        build_node "bca"
      end
    end
    build_node "c"

    @builder.finish_trace(Time.now.to_f)
    validate_builder

    dump = Marshal.dump @builder.sample
    sample = Marshal.restore(dump)
    validate_node(sample.root_node)
  end

  def test_parallel_first_level_nodes
    build_node "a" do
      build_node "ab"
    end
    build_node "b"
    build_node "c"

    @builder.finish_trace(Time.now.to_f)
    validate_builder
  end

  def test_trace_should_not_record_more_than_node_limit
    with_config(:'transaction_tracer.limit_segments' => 3) do
      8.times {|i| build_node i.to_s }
      assert_equal 3, @builder.sample.count_nodes
    end
  end

  def test_trace_has_valid_durations_when_nodes_limited
    with_config(:'transaction_tracer.limit_segments' => 3) do
      build_node "parent" do
        advance_time 1
        build_node "child-0.0" do
          advance_time 1
          build_node "child-0.1" do
            advance_time 1
          end
        end
        advance_time 1
        build_node "child-1.0" do
          advance_time 1
          build_node "child-1.1" do
            advance_time 1
          end
        end
      end

      sample = @builder.sample
      assert_equal(3, sample.count_nodes)

      node_names = []
      node_durations = []
      sample.each_node do |s|
        if s != sample.root_node
          node_names << s.metric_name
          node_durations << s.duration
        end
      end

      assert_equal(["parent", "child-0.0", "child-0.1"], node_names)
      assert_equal([6.0, 2.0, 1.0], node_durations)
    end
  end

  def test_attaching_params_doesnt_raise_when_nodes_are_limited
    with_config(:'transaction_tracer.limit_segments' => 5) do
      6.times { |i| build_node "s#{i}" }
      # now we should have a placeholder node
      build_node "this-should-be-truncated" do
        @builder.current_node['eggs'] = 'ham'
        @builder.current_node.params.merge!('foo' => 'bar')
      end
    end
  end

  def test_finish_trace_records_threshold
    with_config(:'transaction_tracer.transaction_threshold' => 2.0) do
      @builder.finish_trace
      assert_equal 2.0, @builder.sample.threshold
    end
  end

  # regression
  def test_trace_should_log_node_reached_once
    with_config(:'transaction_tracer.limit_segments' => 3) do
      expects_logging(:debug, includes("Node limit"))
      8.times {|i| build_node i.to_s }
    end
  end

  def test_has_correct_transaction_trace_threshold_when_default
    in_transaction do
      with_config(:apdex_t => 1.5) do
        assert_equal 6.0, @builder.transaction_trace_threshold
      end

      with_config(:apdex_t => 2.0) do
        assert_equal 8.0, @builder.transaction_trace_threshold
      end
    end
  end

  def test_has_correct_transaction_trace_threshold_when_explicitly_specified
    config = { :'transaction_tracer.transaction_threshold' => 4.0 }

    in_transaction do
      with_config(config) do
        NewRelic::Agent::TransactionState.tl_get.current_transaction.stubs(:apdex_t).returns(1.5)
        assert_equal 4.0, @builder.transaction_trace_threshold
      end
    end
  end

  def validate_builder(check_names = true)
    validate_node @builder.sample.root_node, check_names
  end

  def validate_node(s, check_names = true)
    p = s.parent_node

    unless p.nil? || p.metric_name == 'ROOT'
      assert p.called_nodes.include?(s)
      assert_equal p.metric_name.length, s.metric_name.length - 1, "p: #{p.metric_name}, s: #{s.metric_name}" if check_names
      assert p.metric_name < s.metric_name if check_names
      assert p.entry_timestamp <= s.entry_timestamp
    end

    assert s.exit_timestamp >= s.entry_timestamp

    children = s.called_nodes
    parent = s
    children.each do |child|
      if check_names
        assert(child.metric_name > parent.metric_name,
               "#{child.metric_name} !> #{parent.metric_name}")
      end
      assert(child.entry_timestamp >= parent.entry_timestamp,
             "#{child.entry_timestamp} !>= #{parent.entry_timestamp}")

      validate_node(child, check_names)
    end
  end

  def build_node(metric, time = 0, &proc)
    @builder.trace_entry(Time.now.to_f)
    proc.call if proc
    @builder.trace_exit(metric, Time.now.to_f)
  end
end
