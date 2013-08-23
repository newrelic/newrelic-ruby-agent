# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransationSampleBuilderTest < Test::Unit::TestCase

  def setup
    freeze_time
    @builder = NewRelic::Agent::TransactionSampleBuilder.new
  end

  # if it doesn't the core app tests will break.  Not strictly necessary but
  # we'll enforce it with this test for now.
  def test_trace_entry_returns_segment
    segment = @builder.trace_entry(Time.now)
    assert segment, "Segment should not be nil"
    assert segment.is_a?(NewRelic::TransactionSample::Segment), "Segment should not be a #{segment.class.name}"
  end

  def test_build_sample
    build_segment("a") do
      build_segment("aa") do
        build_segment("aaa")
      end
      build_segment("ab") do
        build_segment("aba") do
          build_segment("abaa")
        end
        build_segment("aba")
        build_segment("abc") do
          build_segment("abca")
          build_segment("abcd")
        end
      end
    end
    build_segment "b"
    build_segment "c" do
      build_segment "ca"
      build_segment "cb" do
        build_segment "cba"
      end
    end

    @builder.finish_trace(Time.now.to_f)
    validate_builder
  end

  def test_freeze
    build_segment "a" do
      build_segment "aa"
    end

    begin
      builder.sample
      assert false
    rescue => e
      # expected
    end

    @builder.finish_trace(Time.now.to_f)

    validate_builder

    begin
      build_segment "b"
      assert false
    rescue TypeError => e
      # expected
    end
  end

  # this is really a test for transaction sample
  def test_omit_segments_with
    build_segment "Controller/my_controller/index" do
      advance_time 0.010

      build_segment "Rails/Application Code Loading" do
        advance_time 0.020

        build_segment "foo/bar" do
          advance_time 0.010
        end
      end

      build_segment "a" do
        build_segment "ab"
        advance_time 0.010
      end
      build_segment "b" do
        build_segment "ba"
        advance_time 0.05
        build_segment "bb"
        build_segment "bc" do
          build_segment "bca"
          advance_time 0.05
        end
      end
      build_segment "c"
    end
    @builder.finish_trace(Time.now.to_f)

    validate_builder false

    sample = @builder.sample

    should_be_a_copy = sample.omit_segments_with('OMIT NOTHING')
    validate_segment should_be_a_copy.root_segment, false

    assert_equal sample.params, should_be_a_copy.params
    assert_equal(sample.root_segment.to_debug_str(0),
                 should_be_a_copy.root_segment.to_debug_str(0))

    without_code_loading = sample.omit_segments_with('Rails/Application Code Loading')
    validate_segment without_code_loading.root_segment, false

    # after we take out code loading, the delta should be approximately
    # 30 milliseconds
    delta = (sample.duration - without_code_loading.duration) * 1000

    # Need to allow substantial headroom on the upper bound to prevent
    # spurious errors.
    assert delta >= 28, "delta #{delta} should be between 28 and 100"
    # disable this test for a couple days:
    assert delta <= 100, "delta #{delta} should be between 28 and 100"

    # ensure none of the segments have this regex
    without_code_loading.each_segment do |segment|
      assert_nil segment.metric_name =~ /Rails\/Application Code Loading/
    end
  end

  def test_marshal
    build_segment "a" do
      build_segment "ab"
    end
    build_segment "b" do
      build_segment "ba"
      build_segment "bb"
      build_segment "bc" do
        build_segment "bca"
      end
    end
    build_segment "c"

    @builder.finish_trace(Time.now.to_f)
    validate_builder

    dump = Marshal.dump @builder.sample
    sample = Marshal.restore(dump)
    validate_segment(sample.root_segment)
  end

  def test_parallel_first_level_segments
    build_segment "a" do
      build_segment "ab"
    end
    build_segment "b"
    build_segment "c"

    @builder.finish_trace(Time.now.to_f)
    validate_builder
  end

  def test_trace_should_not_record_more_than_segment_limit
    with_config(:'transaction_tracer.limit_segments' => 3) do
      8.times {|i| build_segment i.to_s }
      assert_equal 3, @builder.sample.count_segments
    end
  end

  def test_trace_has_valid_durations_when_segments_limited
    with_config(:'transaction_tracer.limit_segments' => 3) do
      build_segment "parent" do
        advance_time 1
        build_segment "child-0.0" do
          advance_time 1
          build_segment "child-0.1" do
            advance_time 1
          end
        end
        advance_time 1
        build_segment "child-1.0" do
          advance_time 1
          build_segment "child-1.1" do
            advance_time 1
          end
        end
      end

      sample = @builder.sample
      assert_equal(3, sample.count_segments)

      segment_names = []
      segment_durations = []
      sample.each_segment do |s|
        if s != sample.root_segment
          segment_names << s.metric_name
          segment_durations << s.duration
        end
      end

      assert_equal(["parent", "child-0.0", "child-0.1"], segment_names)
      assert_equal([6.0, 2.0, 1.0], segment_durations)
    end
  end

  def test_attaching_params_doesnt_raise_when_segments_are_limited
    with_config(:'transaction_tracer.limit_segments' => 5) do
      6.times { |i| build_segment "s#{i}" }
      # now we should have a placeholder segment
      build_segment "this-should-be-truncated" do
        assert_nothing_raised do
          @builder.current_segment['eggs'] = 'ham'
          @builder.current_segment.params.merge!('foo' => 'bar')
        end
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
  def test_trace_should_log_segment_reached_once
    with_config(:'transaction_tracer.limit_segments' => 3) do
      expects_logging(:debug, includes("Segment limit"))
      8.times {|i| build_segment i.to_s }
    end
  end

  def test_has_correct_transaction_trace_threshold_when_default
    NewRelic::Agent::TransactionState.get.transaction = stub()
    NewRelic::Agent::TransactionState.get.transaction.stubs(:apdex_t).returns(1.5)
    assert_equal 6.0, @builder.transaction_trace_threshold

    NewRelic::Agent::TransactionState.get.transaction.stubs(:apdex_t).returns(2.0)
    assert_equal 8.0, @builder.transaction_trace_threshold
  end

  def test_has_correct_transaction_trace_threshold_when_explicitly_specified
    config = { :'transaction_tracer.transaction_threshold' => 4.0 }

    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::TransactionState.get.transaction = stub()
      NewRelic::Agent::TransactionState.get.transaction.stubs(:apdex_t).returns(1.5)
      assert_equal 4.0, @builder.transaction_trace_threshold
    end
  end

  def validate_builder(check_names = true)
    validate_segment @builder.sample.root_segment, check_names
  end

  def validate_segment(s, check_names = true)
    p = s.parent_segment

    unless p.nil? || p.metric_name == 'ROOT'
      assert p.called_segments.include?(s)
      assert_equal p.metric_name.length, s.metric_name.length - 1, "p: #{p.metric_name}, s: #{s.metric_name}" if check_names
      assert p.metric_name < s.metric_name if check_names
      assert p.entry_timestamp <= s.entry_timestamp
    end

    assert s.exit_timestamp >= s.entry_timestamp

    children = s.called_segments
    parent = s
    children.each do |child|
      if check_names
        assert(child.metric_name > parent.metric_name,
               "#{child.metric_name} !> #{parent.metric_name}")
      end
      assert(child.entry_timestamp >= parent.entry_timestamp,
             "#{child.entry_timestamp} !>= #{parent.entry_timestamp}")
      last_metric = child

      validate_segment(child, check_names)
    end
  end

  def build_segment(metric, time = 0, &proc)
    @builder.trace_entry(Time.now.to_f)
    proc.call if proc
    @builder.trace_exit(metric, Time.now.to_f)
  end
end
