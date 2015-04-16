# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Transaction
  class XraySampleBufferTest < Minitest::Test

    XRAY_SESSION_ID = 123
    MATCHING_TRANSACTION = "Matching/transaction/name"

    def setup
      @xray_session_collection = stub
      @xray_session_collection.stubs(:session_id_for_transaction_name).with(any_parameters).returns(nil)
      @xray_session_collection.stubs(:session_id_for_transaction_name).with(MATCHING_TRANSACTION).returns(XRAY_SESSION_ID)

      @buffer = XraySampleBuffer.new
      @buffer.xray_session_collection = @xray_session_collection
    end

    def test_doesnt_store_if_not_matching_transaction
      sample = sample_with(:transaction_name => "Meaningless/transaction/name")
      @buffer.store(sample)

      assert @buffer.samples.empty?
    end

    def test_stores_if_matching_transaction
      sample = sample_with(:transaction_name => MATCHING_TRANSACTION)
      @buffer.store(sample)

      assert_equal([sample], @buffer.samples)
    end

    def test_stores_and_marks_xray_session_id
      sample = sample_with(:transaction_name => MATCHING_TRANSACTION)
      @buffer.store(sample)

      assert_equal(XRAY_SESSION_ID, sample.xray_session_id)
    end

    def test_limits_xray_traces
      tons_o_samples = max_samples * 2
      samples = (0..tons_o_samples).map do |i|
        sample = sample_with(:transaction_name => MATCHING_TRANSACTION)
        @buffer.store(sample)
        sample
      end

      assert_equal(samples.first(max_samples), @buffer.samples)
    end

    def test_can_disable_via_config
      with_config(:'xray_session.allow_traces' => false) do
        assert_false @buffer.enabled?
      end
    end

    def max_samples
      NewRelic::Agent.config[:'xray_session.max_samples']
    end

    def sample_with(opts={})
      sample = NewRelic::Agent::Transaction::Trace.new(Time.now)
      sample.transaction_name = opts[:transaction_name]
      sample
    end

  end
end
