# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/external'

module NewRelic
  module Agent
    class ExternalTest < Minitest::Test

      TRANSACTION_GUID = 'BEC1BC64675138B9'

      def setup
        @obfuscator = NewRelic::Agent::Obfuscator.new "jotorotoes"
        CrossAppTracing.stubs(:obfuscator).returns(@obfuscator)
        CrossAppTracing.stubs(:valid_encoding_key?).returns(true)
      end

      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      def test_start_segment_starts_an_external_segment
        s = NewRelic::Agent::External.start_segment library: 'Net::HTTP',
                                                    uri: 'https://example.com/foobar',
                                                    procedure: 'GET'
        assert_instance_of NewRelic::Agent::Transaction::ExternalRequestSegment, s
      end

      # --- process_request_metadata

      def test_process_request_metadata
        with_config cat_config do
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi']
          })

          in_transaction do |txn|
            NewRelic::Agent::External.process_request_metadata rmd
            assert_equal cat_config[:cross_process_id], txn.client_cross_app_id
            assert_equal ['abc', false, 'def', 'ghi'], txn.referring_transaction_info
          end
        end
      end

      def test_process_request_metadata_with_synthetics
        with_config cat_config do
          raw_synth = @obfuscator.obfuscate ::JSON.dump('raw_synth')

          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          in_transaction do |txn|
            NewRelic::Agent::External.process_request_metadata rmd

            assert_equal raw_synth, txn.raw_synthetics_header
            assert_equal 'raw_synth', txn.synthetics_payload
          end
        end
      end

      def test_process_request_metadata_not_in_transaction
        with_config cat_config do
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          l = with_array_logger { NewRelic::Agent::External.process_request_metadata rmd }
          assert l.array.empty?, "process_request_metadata should not log errors without a current transaction"

          state = NewRelic::Agent::TransactionState.tl_get
          refute state.current_transaction
        end
      end

      def test_process_request_metadata_with_invalid_id
        with_config cat_config do
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: 'bugz',
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          in_transaction do |txn|
            l = with_array_logger { NewRelic::Agent::External.process_request_metadata rmd }
            refute l.array.empty?, "process_request_metadata should log error on invalid ID"
            assert l.array.first =~ %r{invalid/non-trusted ID}

            state = NewRelic::Agent::TransactionState.tl_get
            refute txn.client_cross_app_id
            refute txn.referring_transaction_info
          end
        end
      end

      def test_process_request_metadata_with_non_trusted_id
        with_config cat_config do
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: '190#666',
            NewRelicTransaction: ['abc', false, 'def', 'ghi'],
            NewRelicSynthetics: 'raw_synth'
          })

          in_transaction do |txn|
            l = with_array_logger { NewRelic::Agent::External.process_request_metadata rmd }
            refute l.array.empty?, "process_request_metadata should log error on invalid ID"
            assert l.array.first =~ %r{invalid/non-trusted ID}

            state = NewRelic::Agent::TransactionState.tl_get
            refute txn.client_cross_app_id
            refute txn.referring_transaction_info
          end
        end
      end

      def test_process_request_metadata_cross_app_disabled
        with_config cat_config.merge(:'cross_application_tracer.enabled' => false) do
          rmd = @obfuscator.obfuscate ::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi']
          })

          in_transaction do |txn|
            l = with_array_logger { NewRelic::Agent::External.process_request_metadata rmd }
            assert l.array.empty?, "process_request_metadata should not log errors when cross app tracing is disabled"

            state = NewRelic::Agent::TransactionState.tl_get
            refute txn.client_cross_app_id
            refute txn.referring_transaction_info
          end
        end
      end

      # --- get_response_metadata

      def test_get_response_metadata
        with_config cat_config do
          in_transaction do |txn|

            # simulate valid processed request metadata
            txn.client_cross_app_id = "1#666"

            rmd = NewRelic::Agent::External.get_response_metadata
            assert_instance_of String, rmd
            rmd = @obfuscator.deobfuscate rmd
            rmd = JSON.parse rmd
            assert_instance_of Hash, rmd
            assert_instance_of Array, rmd['NewRelicAppData']

            assert_equal '269975#22824', rmd['NewRelicAppData'][0]
            assert_equal 'dummy', rmd['NewRelicAppData'][1]
            assert_instance_of Float, rmd['NewRelicAppData'][2]
            assert_instance_of Float, rmd['NewRelicAppData'][3]
            assert_equal -1, rmd['NewRelicAppData'][4]
            assert_equal txn.guid, rmd['NewRelicAppData'][5]
          end
        end
      end

      def test_get_response_metadata_not_in_transaction
        with_config cat_config do
          refute NewRelic::Agent::External.get_response_metadata
        end
      end

      def test_get_response_metadata_without_valid_id
        with_config cat_config do
          in_transaction do |txn|
            refute NewRelic::Agent::External.get_response_metadata
          end
        end
      end

      # ---

      def cat_config
        {
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled' => false,
          :cross_process_id => "269975#22824",
          :trusted_account_ids => [1,269975]
        }
      end

    end
  end
end
