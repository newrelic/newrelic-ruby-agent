# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../test_helper.rb', __FILE__)
require 'new_relic/rack/developer_mode'

class NewRelic::TransactionSampleTest < Minitest::Test
  include TransactionSampleTestHelper

  ::SQL_STATEMENT = "SELECT * from sandwiches WHERE meat='bacon'"
  ::OBFUSCATED_SQL_STATEMENT = "SELECT * from sandwiches WHERE meat=?"

  FORCE_PERSIST_POSITION = 7
  SYNTHETICS_POSITION    = 9

  def setup
    @test_config = { :developer_mode => true }
    NewRelic::Agent.config.add_config_for_testing(@test_config)

    NewRelic::Agent.agent.transaction_sampler.reset!

    @connection_stub = Mocha::Mockery.instance.named_mock('connection')
    @connection_stub.stubs(:execute).returns(dummy_mysql_explain_result({'foo' => 'bar'}))

    NewRelic::Agent::Database.stubs(:get_connection).returns @connection_stub
    @t = make_sql_transaction(::SQL_STATEMENT)

    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      @marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
    else
      @marshaller = NewRelic::Agent::NewRelicService::PrubyMarshaller.new
    end

  end

  def teardown
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def test_be_recorded
    refute_nil @t
  end

  def test_prepare_to_send_strips_sql_if_record_sql_is_off_or_none_or_false
    record_sql_values = %w(off none false)
    record_sql_values.each do |record_sql_value|
      s = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
      with_config(:'transaction_tracer.record_sql' => record_sql_value) do
        s.prepare_to_send!
        s.each_segment do |segment|
          assert_nil segment.params[:explain_plan]
          assert_nil segment.params[:sql]
        end
      end
    end
  end

  def test_prepare_to_send_preserves_raw_sql_if_record_sql_set_to_raw
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      @t.prepare_to_send!
    end

    sql_statements = extract_captured_sql(@t)
    assert_equal([::SQL_STATEMENT], sql_statements)
  end

  def test_prepare_to_send_obfuscates_sql_if_record_sql_set_to_obfuscated
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      @t.prepare_to_send!
    end

    sql_statements = extract_captured_sql(@t)
    assert_equal([::OBFUSCATED_SQL_STATEMENT], sql_statements)
  end

  def test_have_sql_rows_when_sql_is_recorded
    with_config(:'transaction_tracer.record_sql' => 'off') do
      @t.prepare_to_send!
    end

    assert @t.sql_segments.empty?
    @t.root_segment[:sql] = 'hello'
    assert !@t.sql_segments.empty?
  end

  def test_have_sql_rows_when_sql_is_obfuscated
    with_config(:'transaction_tracer.record_sql' => 'off') do
      @t.prepare_to_send!
    end

    assert @t.sql_segments.empty?
    @t.root_segment[:sql_obfuscated] = 'hello'
    assert !@t.sql_segments.empty?
  end

  def test_have_sql_rows_when_recording_non_sql_keys
    with_config(:'transaction_tracer.record_sql' => 'off') do
      @t.prepare_to_send!
    end

    assert @t.sql_segments.empty?
    @t.root_segment[:key] = 'hello'
    assert !@t.sql_segments.empty?
  end

  def test_catch_exceptions
    config = {
      :'transaction_tracer.record_sql'        => 'obfuscated',
      :'transaction_tracer.explain_enabled'   => true,
      :'transaction_tracer.explain_threshold' => 0.00000001
    }

    @connection_stub.expects(:execute).raises
    with_config(config) do
      @t.prepare_to_send!
    end
  end

  def test_have_explains
    config = {
      :'transaction_tracer.record_sql'        => 'obfuscated',
      :'transaction_tracer.explain_enabled'   => true,
      :'transaction_tracer.explain_threshold' => 0.00000001
    }

    with_config(config) do
      @t.prepare_to_send!
    end

    @t.each_segment do |segment|
      if segment.params[:explain_plan]
        explanation = segment.params[:explain_plan]

        assert_kind_of Array, explanation
        assert_equal([['foo'], [['bar']]], explanation)
      end
    end
  end

  def test_not_record_transactions
    NewRelic::Agent.instance.transaction_sampler.reset!

    NewRelic::Agent.disable_transaction_tracing do
      t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
      assert t.nil?
    end
  end

  def test_path_string
    s = @t.prepare_to_send!
    fake_segment = mock('segment')
    fake_segment.expects(:path_string).returns('a path string')
    s.instance_eval do
      @root_segment = fake_segment
    end

    assert_equal('a path string', s.path_string)
  end

  def test_params_equals
    s = @t.prepare_to_send!
    s.params = {:params => 'hash' }
    assert_equal({:params => 'hash'}, s.params, "should have the specified hash, but instead was #{s.params}")
  end

  class Hat
    # just here to mess with the to_s logic in transaction samples
  end

  def test_to_s_with_bad_object
    @t.prepare_to_send!
    @t.params[:fake] = Hat.new
    assert_raises(RuntimeError) do
      @t.to_s
    end
  end

  def test_to_s_includes_keys
    @t.prepare_to_send!
    @t.params[:fake_key] = 'a fake param'
    assert(@t.to_s.include?('fake_key'), "should include 'fake_key' but instead was (#{@t.to_s})")
    assert(@t.to_s.include?('a fake param'), "should include 'a fake param' but instead was (#{@t.to_s})")
  end

  def test_find_segment
    s = @t.prepare_to_send!
    fake_segment = mock('segment')
    fake_segment.expects(:find_segment).with(1).returns('a segment')
    s.instance_eval do
      @root_segment = fake_segment
    end

    assert_equal('a segment', s.find_segment(1))
  end

  def test_timestamp
    s = @t.prepare_to_send!
    assert(s.timestamp.instance_of?(Float), "s.timestamp should be a Float, but is #{s.timestamp.class.inspect}")
  end

  def test_xray_session_id
    @t.xray_session_id = 123
    s = @t.prepare_to_send!
    assert_equal(123, s.xray_session_id)
  end

  def test_prepare_to_send_marks_returned_sample_as_prepared
    assert(!@t.prepared?)
    prepared_sample = @t.prepare_to_send!
    assert(prepared_sample.prepared?)
  end

  def test_prepare_to_send_does_not_re_prepare
    @t.prepare_to_send!
    @t.expects(:collect_explain_plans!).never
    @t.expects(:prepare_sql_for_transmission!).never
    @t.prepare_to_send!
  end

  def test_threshold_preserved_by_prepare_to_send
    @t.threshold = 4.2
    s = @t.prepare_to_send!
    assert_equal(4.2, s.threshold)
  end

  def test_count_segments
    transaction = run_sample_trace do |sampler|
      state = NewRelic::Agent::TransactionState.tl_get
      sampler.notice_push_frame(state, "level0")
      sampler.notice_push_frame(state, "level-1")
      sampler.notice_push_frame(state, "level-2")
      sampler.notice_sql(::SQL_STATEMENT, {}, 0, state)
      sampler.notice_pop_frame(state, "level-2")
      sampler.notice_pop_frame(state, "level-1")
      sampler.notice_pop_frame(state, "level0")
    end

    assert_equal 6, transaction.count_segments
  end

  def test_to_array
    # Round-trip through Time.at makes minor rounding diffs in Rubinius
    # Check each element separately so we can reconcile the delta
    result = @t.to_array
    assert_equal 4, result.length

    assert_in_delta(@t.start_time.to_f, result[0], 0.000001)
    assert_equal @t.params[:request_params], result[1]
    assert_equal @t.params[:custom_params], result[2]
    assert_equal @t.root_segment.to_array, result[3]
  end


  def test_to_array_with_bad_values
    transaction = NewRelic::TransactionSample.new(nil)
    expected = [0.0, {}, nil, [0, 0, "ROOT", {}, []]]
    assert_equal expected, transaction.to_array
  end

  def test_to_collector_array
    expected_array = [(@t.start_time.to_f * 1000).round,
                      (@t.duration * 1000).round,
                      @t.params[:path], @t.params[:uri],
                      trace_tree,
                      @t.guid, nil, !!@t.force_persist,
                      @t.xray_session_id,
                      @t.synthetics_resource_id]

    assert_collector_arrays_match expected_array, @t.to_collector_array(@marshaller.default_encoder)

  end

  def assert_collector_arrays_match(expected_array, actual_array)
    expected_array[4] = expand_trace_tree(expected_array[4])
    actual_array[4]   = expand_trace_tree(actual_array[4])

    assert_equal expected_array, actual_array
  end

  def test_to_collector_array_forces_xrays
    @t.force_persist = false
    @t.xray_session_id = 123
    result = @t.to_collector_array(@marshaller.default_encoder)
    assert_equal true, result[FORCE_PERSIST_POSITION]
  end

  def test_to_collector_array_uses_synthetics_resource_id
    @t.synthetics_resource_id = '42'
    result = @t.to_collector_array(@marshaller.default_encoder)
    assert_equal '42', result[SYNTHETICS_POSITION]
  end

  def test_to_collector_array_with_bad_values
    transaction = NewRelic::TransactionSample.new(nil)
    transaction.root_segment.end_trace(Rational(10, 1))
    transaction.xray_session_id = "booooooo"

    expected = [
      0, 10_000,
      nil, nil,
      trace_tree(transaction),
      transaction.guid,
      nil, false, nil, nil]

    actual = transaction.to_collector_array(@marshaller.default_encoder)
    assert_collector_arrays_match expected, actual
  end

  INVALID_UTF8_STRING = (''.respond_to?(:force_encoding) ? "\x80".force_encoding('UTF-8') : "\x80")

  def test_prepare_to_send_with_incorrectly_encoded_string_in_sql_query
    query = "SELECT * FROM table WHERE col1=\"#{INVALID_UTF8_STRING}\" AND col2=\"whatev\""

    t = nil
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      t = make_sql_transaction(query)
      t.prepare_to_send!
    end

    sql_statements = extract_captured_sql(t)
    assert_equal(["SELECT * FROM table WHERE col1=? AND col2=?"], sql_statements)
  end

  def test_multiple_calls_to_notice_sequel_appends_sql
    queries = ["BEGIN", "INSERT items(title) VALUES('title')", "COMMIT"]

    t = make_sql_transaction(*queries)
    sql_statements = extract_captured_sql(t)

    assert_equal [queries.join("\n")], sql_statements
  end

  def trace_tree(transaction=@t)
    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      trace_tree = compress(JSON.dump(transaction.to_array))
    else
      trace_tree = transaction.to_array
    end
  end

  def compress(string)
    Base64.encode64(Zlib::Deflate.deflate(string, Zlib::DEFAULT_COMPRESSION))
  end

  def expand_trace_tree(encoded_tree)
    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      JSON.load(Zlib::Inflate.inflate(Base64.decode64(encoded_tree)))
    else
      encoded_tree
    end
  end

  def extract_captured_sql(trace)
    sqls = []
    trace.each_segment do |s|
      sqls << s.params[:sql]
    end
    sqls.compact
  end
end
