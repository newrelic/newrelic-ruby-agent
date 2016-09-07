# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/external_request_segment'

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegmentTest < Minitest::Test

        TRANSACTION_GUID = 'BEC1BC64675138B9'

        def test_generates_expected_name
          segment = ExternalRequestSegment.new "Typhoeus", "http://remotehost.com/blogs/index", "GET"
          assert_equal "External/remotehost.com/Typhoeus/GET", segment.name
        end

        def test_segment_records_expected_metrics_for_non_cat_txn
          in_transaction :category => :controller do
            segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
            segment.finish
          end

          expected_metrics = [
            "External/remotehost.com/Net::HTTP/GET",
            "External/all",
            "External/remotehost.com/all",
            "External/allWeb"
          ]

          assert_metrics_recorded expected_metrics
        end

        def test_segment_writes_outbound_request_headers
          headers = {}
          with_config cat_config do
            in_transaction :category => :controller do
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
              segment.add_request_headers headers
              segment.finish
            end
          end
          assert headers.key?("X-NewRelic-ID"), "Expected to find X-NewRelic-ID header"
          assert headers.key?("X-NewRelic-Transaction"), "Expected to find X-NewRelic-Transaction header"
        end

        def test_segment_writes_sythetics_header_for_synthetics_txn
          headers = {}
          with_config cat_config do
            in_transaction :category => :controller do |txn|
              txn.raw_synthetics_header = json_dump_and_encode [1, 42, 100, 200, 300]
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
              segment.add_request_headers headers
              segment.finish
            end
          end
          assert headers.key?("X-NewRelic-Synthetics"), "Expected to find X-NewRelic-Synthetics header"
        end

        def test_read_response_headers_decodes_valid_appdata
          response = {
            'X-NewRelic-App-Data' => make_app_data_payload("1#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID)
          }

          with_config cat_config do
            in_transaction :category => :controller do |txn|
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
              segment.read_response_headers response
              segment.finish

              assert segment.cross_app_request?
              assert_equal "1#1884", segment.cross_process_id
              assert_equal "txn-name", segment.cross_process_transaction_name
              assert_equal "BEC1BC64675138B9", segment.transaction_guid
            end
          end
        end

        def test_read_response_headers_ignores_invalid_appdata
          response = {
            'X-NewRelic-App-Data' => "this#is#not#valid#appdata"
          }

          with_config cat_config do
            in_transaction :category => :controller do |txn|
              segment = Transaction.start_external_request_segment "Net::HTTP", "http://remotehost.com/blogs/index", "GET"
              segment.read_response_headers response
              segment.finish

              refute segment.cross_app_request?
              assert_nil segment.cross_process_id
              assert_nil segment.cross_process_transaction_name
              assert_nil segment.transaction_guid
            end
          end
        end

        def cat_config
          {
            :cross_process_id    => "269975#22824",
            :encoding_key        => "jotorotoes",
            :trusted_account_ids => [1,269975]
          }
        end

        def make_app_data_payload( *args )
          obfuscator = NewRelic::Agent::Obfuscator.new("jotorotoes")
          return obfuscator.obfuscate( args.to_json ) + "\n"
        end
      end
    end
  end
end
