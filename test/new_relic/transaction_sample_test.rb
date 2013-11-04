# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../test_helper.rb', __FILE__)

class NewRelic::TransactionSampleTest < Test::Unit::TestCase
  include TransactionSampleTestHelper
  ::SQL_STATEMENT = "SELECT * from sandwiches WHERE meat='bacon'"
  ::OBFUSCATED_SQL_STATEMENT = "SELECT * from sandwiches WHERE meat=?"

  def setup
    @test_config = { :developer_mode => true }
    NewRelic::Agent.config.apply_config(@test_config)
    @connection_stub = Mocha::Mockery.instance.named_mock('connection')
    @connection_stub.stubs(:execute).returns([['QUERY RESULT']])

    NewRelic::Agent::Database.stubs(:get_connection).returns @connection_stub
    @t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)

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
    assert_not_nil @t
  end

  def test_prepare_to_send_strips_sql_if_record_sql_omitted
    s = @t.prepare_to_send!(:explain_sql => 0.00000001)

    s.each_segment do |segment|
      assert_nil segment.params[:explain_plan]
      assert_nil segment.params[:sql]
    end
  end

  def test_prepare_to_send_preserves_raw_sql_if_record_sql_set_to_raw
    s = @t.prepare_to_send!(:record_sql => :raw)

    sql_statements = []
    s.each_segment do |segment|
      sql_statements << segment.params[:sql] if segment.params[:sql]
    end

    assert_equal([::SQL_STATEMENT], sql_statements)
  end

  def test_prepare_to_send_obfuscates_sql_if_record_sql_set_to_obfuscated
    s = @t.prepare_to_send!(:record_sql => :obfuscated)

    sql_statements = []
    s.each_segment do |segment|
      sql_statements << segment.params[:sql] if segment.params[:sql]
    end

    assert_equal([::OBFUSCATED_SQL_STATEMENT], sql_statements)
  end

  def test_have_sql_rows_when_sql_is_recorded
    s = @t.prepare_to_send!(:explain_sql => 0.00000001)

    assert s.sql_segments.empty?
    s.root_segment[:sql] = 'hello'
    assert !s.sql_segments.empty?
  end

  def test_have_sql_rows_when_sql_is_obfuscated
    s = @t.prepare_to_send!(:explain_sql => 0.00000001)

    assert s.sql_segments.empty?
    s.root_segment[:sql_obfuscated] = 'hello'
    assert !s.sql_segments.empty?
  end

  def test_have_sql_rows_when_recording_non_sql_keys
    s = @t.prepare_to_send!(:explain_sql => 0.00000001)

    assert s.sql_segments.empty?
    s.root_segment[:key] = 'hello'
    assert !s.sql_segments.empty?
  end

  def test_catch_exceptions
    @connection_stub.expects(:execute).raises
    # the sql connection will throw
    @t.prepare_to_send!(:record_sql => :obfuscated, :explain_sql => 0.00000001)
  end

  def test_have_explains
    s = @t.prepare_to_send!(:record_sql => :obfuscated, :explain_sql => 0.00000001)

    s.each_segment do |segment|
      if segment.params[:explain_plan]
        explanation = segment.params[:explain_plan]

        assert_kind_of Array, explanation
        assert_equal([nil, [["QUERY RESULT"]]], explanation)
      end
    end
  end

  def test_not_record_sql_without_record_sql_option
    t = nil
    NewRelic::Agent.disable_sql_recording do
      t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
    end

    s = t.prepare_to_send!(:explain_sql => 0.00000001)

    s.each_segment do |segment|
      assert_nil segment.params[:explain_plan]
      assert_nil segment.params[:sql]
    end
  end

  def test_not_record_transactions
    NewRelic::Agent.disable_transaction_tracing do
      t = make_sql_transaction(::SQL_STATEMENT, ::SQL_STATEMENT)
      assert t.nil?
    end
  end

  def test_path_string
    s = @t.prepare_to_send!(:explain_sql => 0.1)
    fake_segment = mock('segment')
    fake_segment.expects(:path_string).returns('a path string')
    s.instance_eval do
      @root_segment = fake_segment
    end

    assert_equal('a path string', s.path_string)
  end

  def test_params_equals
    s = @t.prepare_to_send!(:explain_sql => 0.1)
    s.params = {:params => 'hash' }
    assert_equal({:params => 'hash'}, s.params, "should have the specified hash, but instead was #{s.params}")
  end

  class Hat
    # just here to mess with the to_s logic in transaction samples
  end

  def test_to_s_with_bad_object
    s = @t.prepare_to_send!(:explain_sql => 0.1)
    s.params[:fake] = Hat.new
    assert_raise(RuntimeError) do
      s.to_s
    end
  end

  def test_to_s_includes_keys
    s = @t.prepare_to_send!(:explain_sql => 0.1)
    s.params[:fake_key] = 'a fake param'
    assert(s.to_s.include?('fake_key'), "should include 'fake_key' but instead was (#{s.to_s})")
    assert(s.to_s.include?('a fake param'), "should include 'a fake param' but instead was (#{s.to_s})")
  end

  def test_find_segment
    s = @t.prepare_to_send!(:explain_sql => 0.1)
    fake_segment = mock('segment')
    fake_segment.expects(:find_segment).with(1).returns('a segment')
    s.instance_eval do
      @root_segment = fake_segment
    end

    assert_equal('a segment', s.find_segment(1))
  end

  def test_timestamp
    s = @t.prepare_to_send!(:explain_sql => 0.1)
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
    opts = { :record_sql => :raw, :explain_sql => 0.00001 }
    @t.prepare_to_send!(opts)

    @t.expects(:collect_explain_plans!).never
    @t.expects(:prepare_sql_for_transmission!).never

    @t.prepare_to_send!(opts)
  end

  def test_threshold_preserved_by_prepare_to_send
    @t.threshold = 4.2
    s = @t.prepare_to_send!
    assert_equal(4.2, s.threshold)
  end

  def test_count_segments
    transaction = run_sample_trace_on(NewRelic::Agent::TransactionSampler.new) do |sampler|
      sampler.notice_push_scope "level0"
      sampler.notice_push_scope "level-1"
      sampler.notice_push_scope "level-2"
      sampler.notice_sql(::SQL_STATEMENT, {}, 0)
      sampler.notice_pop_scope "level-2"
      sampler.notice_pop_scope "level-1"
      sampler.notice_pop_scope "level0"
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

  if RUBY_VERSION >= '1.9.2'
    def test_to_json
      expected_string = JSON.dump([@t.start_time.to_f,
                                   @t.params[:request_params],
                                   @t.params[:custom_params],
                                   @t.root_segment.to_array])
      assert_equal expected_string, @t.to_json
    end
  end

  def test_to_collector_array
    expected_array = [(@t.start_time.to_f * 1000).round,
                      (@t.duration * 1000).round,
                      @t.params[:path], @t.params[:uri],
                      trace_tree,
                      @t.guid, nil, !!@t.force_persist, @t.xray_session_id]

    assert_equal expected_array, @t.to_collector_array(@marshaller.default_encoder)
  end

  FORCE_PERSIST_POSITION = 7

  def test_to_collector_array_forces_xrays
    @t.force_persist = false
    @t.xray_session_id = 123
    result = @t.to_collector_array(@marshaller.default_encoder)
    assert_equal true, result[FORCE_PERSIST_POSITION]
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
      nil, false, nil]

    assert_equal expected, transaction.to_collector_array(@marshaller.default_encoder)
  end

  def trace_tree(transaction=@t)
    if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
      trace_tree = compress(transaction.to_json)
    else
      trace_tree = transaction.to_array
    end
  end

  def compress(string)
    Base64.encode64(Zlib::Deflate.deflate(string, Zlib::DEFAULT_COMPRESSION))
  end
end
