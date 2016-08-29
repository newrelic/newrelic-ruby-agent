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

        def cat_config
          {
            :cross_process_id    => "269975#22824",
            :encoding_key        => "jotorotoes",
            :trusted_account_ids => [269975]
          }
        end
      end
    end
  end
end
