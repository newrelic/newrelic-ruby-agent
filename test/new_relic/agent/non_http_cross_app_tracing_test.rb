# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../test_helper', __FILE__

module NewRelic::Agent
  class NonHTTPCrossAppTracingTest < Minitest::Test

    CAT_CONFIG = {
      :'cross_application_tracer.enabled' => true,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => "gringletoes",
      :trusted_account_ids                => [269975]
    }

    # --- get_request_metadata

    def test_get_request_metadata
      with_config CAT_CONFIG do
        in_transaction do |txn|
          rmd = NewRelic::Agent::CrossAppTracing::NonHTTP.get_request_metadata
          assert_instance_of String, rmd
          rmd = obfuscator.deobfuscate rmd
          rmd = JSON.parse rmd
          assert_instance_of Hash, rmd

          assert_equal '269975#22824', rmd['NewRelicID']

          assert_instance_of Array, rmd['NewRelicTransaction']
          assert_equal txn.guid, rmd['NewRelicTransaction'][0]
          refute rmd['NewRelicTransaction'][1]

          assert_equal txn.cat_trip_id, rmd['NewRelicTransaction'][2]
          assert_equal txn.cat_path_hash, rmd['NewRelicTransaction'][3]

          refute rmd.key? 'NewRelicSynthetics'
        end
      end
    end

    def test_get_request_metadata_with_synthetics_header
      with_config CAT_CONFIG do
        in_transaction do |txn|
          txn.raw_synthetics_header = 'raw_synth'

          rmd = NewRelic::Agent::CrossAppTracing::NonHTTP.get_request_metadata
          rmd = obfuscator.deobfuscate rmd
          rmd = JSON.parse rmd

          assert_equal 'raw_synth', rmd['NewRelicSynthetics']
        end
      end
    end

    def test_get_request_metadata_not_in_transaction
      with_config CAT_CONFIG do
        refute NewRelic::Agent::CrossAppTracing::NonHTTP.get_request_metadata
      end
    end

    # --- process_request_metadata

    def test_process_request_metadata
      with_config CAT_CONFIG.select {|k,_| k == :encoding_key} do
        rmd = obfuscator.obfuscate ::JSON.dump({
          NewRelicID: CAT_CONFIG[:cross_process_id],
          NewRelicTransaction: ['abc', false, 'def', 'ghi']
        })

        in_transaction do |txn|
          NewRelic::Agent::CrossAppTracing::NonHTTP.process_request_metadata rmd

          assert_equal CAT_CONFIG[:cross_process_id], txn.state.client_cross_app_id
          assert_equal ['abc', false, 'def', 'ghi'], txn.state.referring_transaction_info
        end
      end
    end

    def test_process_request_metadata_with_synthetics
      with_config CAT_CONFIG.select {|k,_| k == :encoding_key} do
        raw_synth = obfuscator.obfuscate ::JSON.dump('raw_synth')

        rmd = obfuscator.obfuscate ::JSON.dump({
          NewRelicID: CAT_CONFIG[:cross_process_id],
          NewRelicTransaction: ['abc', false, 'def', 'ghi'],
          NewRelicSynthetics: 'raw_synth'
        })

        in_transaction do |txn|
          NewRelic::Agent::CrossAppTracing::NonHTTP.process_request_metadata rmd

          assert_equal raw_synth, txn.raw_synthetics_header
          assert_equal 'raw_synth', txn.synthetics_payload
        end
      end
    end

    def test_process_request_metadata_not_in_transaction
      with_config CAT_CONFIG.select {|k,_| k == :encoding_key} do
        rmd = obfuscator.obfuscate ::JSON.dump({
          NewRelicID: CAT_CONFIG[:cross_process_id],
          NewRelicTransaction: ['abc', false, 'def', 'ghi'],
          NewRelicSynthetics: 'raw_synth'
        })

        NewRelic::Agent::CrossAppTracing::NonHTTP.process_request_metadata rmd
        state = NewRelic::Agent::TransactionState.tl_get
        refute state.client_cross_app_id
        refute state.referring_transaction_info
        refute state.current_transaction
      end
    end

    # --- get_response_metadata

    def test_get_response_metadata
      with_config CAT_CONFIG do
        in_transaction do |txn|
          rmd = NewRelic::Agent::CrossAppTracing::NonHTTP.get_response_metadata
          assert_instance_of String, rmd
          rmd = obfuscator.deobfuscate rmd
          rmd = JSON.parse rmd
          assert_instance_of Hash, rmd
          assert_instance_of Array, rmd['NewRelicAppData']

          assert_equal '269975#22824', rmd['NewRelicAppData'][0]
          assert_equal 'dummy', rmd['NewRelicAppData'][1]
          assert_instance_of Float, rmd['NewRelicAppData'][2]
          assert_instance_of Float, rmd['NewRelicAppData'][3]
          assert_equal -1, rmd['NewRelicAppData'][4]
          assert_equal txn.state.request_guid, rmd['NewRelicAppData'][5]
        end
      end
    end

    def test_get_response_metadata_not_in_transaction
      with_config CAT_CONFIG do
        refute NewRelic::Agent::CrossAppTracing::NonHTTP.get_response_metadata
      end
    end

    # --- process_response_metadata

    def test_process_response_metadata
      with_config CAT_CONFIG do
        in_transaction do |txn|

          rmd = obfuscator.obfuscate ::JSON.dump({
            NewRelicAppData: [
              NewRelic::Agent.config[:cross_process_id],
              'Controller/root/index',
              0.001,
              0.5,
              60,
              txn.guid
            ]
          })

          segment = NewRelic::Agent::Transaction.start_external_request_segment :h2, 'https://example.com/root/index', :get
          NewRelic::Agent::CrossAppTracing::NonHTTP.process_response_metadata rmd
          assert_equal 'ExternalTransaction/example.com/269975#22824/Controller/root/index', segment.name
          segment.finish
        end
      end
    end

    def test_process_response_metadata_without_external_request_segment
      with_config CAT_CONFIG do
        in_transaction do |txn|

          rmd = obfuscator.obfuscate ::JSON.dump({
            NewRelicAppData: [
              NewRelic::Agent.config[:cross_process_id],
              'Controller/root/index',
              0.001,
              0.5,
              60,
              txn.guid
            ]
          })

          segment = NewRelic::Agent::Transaction.start_segment 'test_segment'
          NewRelic::Agent::CrossAppTracing::NonHTTP.process_response_metadata rmd
          assert_equal 'test_segment', segment.name
          segment.finish
        end
      end
    end

    def test_process_response_metadata_not_in_transaction
      with_config CAT_CONFIG do

        rmd = obfuscator.obfuscate ::JSON.dump({
          NewRelicAppData: [
            NewRelic::Agent.config[:cross_process_id],
            'Controller/root/index',
            0.001,
            0.5,
            60,
            'abcdef'
          ]
        })

        refute NewRelic::Agent::CrossAppTracing::NonHTTP.process_response_metadata rmd
      end
    end

    private

    # --- helpers

    def obfuscator
      CrossAppTracing.obfuscator
    end

  end
end
