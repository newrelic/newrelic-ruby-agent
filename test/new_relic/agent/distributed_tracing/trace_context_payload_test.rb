# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic
  module Agent
    class TraceContextPayloadTest < Minitest::Test
      def test_to_s
        payload = TraceContextPayload.create \
          parent_account_id: "12345",
          parent_app_id: "6789",
          id: "f85f42fd82a4cf1d",
          transaction_id: "164d3b4b0d09cb05",
          sampled: true,
          priority: 0.123

        assert_equal "0-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123000-#{payload.timestamp}", payload.to_s
      end

      def test_to_s_with_nil_id
        # The id field will be nil if span events are disabled or the transaction is not sampled,
        # and to_s should be able to deal with that.

        payload = TraceContextPayload.create \
          parent_account_id: "12345",
          parent_app_id: "6789",
          transaction_id: "164d3b4b0d09cb05",
          sampled: true,
          priority: 0.123

        assert_equal "0-0-12345-6789--164d3b4b0d09cb05-1-0.123000-#{payload.timestamp}", payload.to_s
      end

      def test_to_s_does_not_convert_to_scientific_notation
        # The id field will be nil if span events are disabled or the transaction is not sampled,
        # and to_s should be able to deal with that.

        payload = TraceContextPayload.create \
          parent_account_id: "12345",
          parent_app_id: "6789",
          transaction_id: "164d3b4b0d09cb05",
          sampled: true,
          priority: 0.000012

        assert_equal "0-0-12345-6789--164d3b4b0d09cb05-1-0.000012-#{payload.timestamp}", payload.to_s
      end

      def test_from_s
        nr_freeze_time

        payload_str = "0-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-#{now_ms}"
        payload = TraceContextPayload.from_s payload_str

        assert_equal 0, payload.version
        assert_equal 0, payload.parent_type_id
        assert_equal "App", payload.parent_type
        assert_equal "12345", payload.parent_account_id
        assert_equal "6789", payload.parent_app_id
        assert_equal "f85f42fd82a4cf1d", payload.id
        assert_equal "164d3b4b0d09cb05", payload.transaction_id
        assert_equal true, payload.sampled
        assert_equal 0.123, payload.priority
      end

      def test_from_s_browser_payload_no_sampled_priority_or_transaction_id
        payload_str = '0-1-212311-51424-0996096a36a1cd29----1482959525577'
        payload = TraceContextPayload.from_s payload_str

        assert_equal 0, payload.version
        assert_equal 1, payload.parent_type_id
        assert_equal "Browser", payload.parent_type
        assert_equal '212311', payload.parent_account_id
        assert_equal '51424', payload.parent_app_id
        assert_equal '0996096a36a1cd29', payload.id
        assert_nil payload.transaction_id
        assert_nil payload.sampled
        assert_nil payload.priority
        assert_equal 1482959525577, payload.timestamp
      end

      def test_additional_attributes
        nr_freeze_time

        payload_str = "1-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-#{now_ms}-futureattr1"
        payload = TraceContextPayload.from_s payload_str

        assert_equal 1, payload.version
        assert_equal 0, payload.parent_type_id
        assert_equal "App", payload.parent_type
        assert_equal "12345", payload.parent_account_id
        assert_equal "6789", payload.parent_app_id
        assert_equal "f85f42fd82a4cf1d", payload.id
        assert_equal "164d3b4b0d09cb05", payload.transaction_id
        assert_equal true, payload.sampled
        assert_equal 0.123, payload.priority
      end

      def test_valid
        valid_payloads = [
          "1-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-1482959525577",
          "1-0-12345-6789--164d3b4b0d09cb05-1-0.123-1482959525577",
          "1-0-12345-6789-f85f42fd82a4cf1d--1-0.123-1482959525577",
          "1-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05--0.123-1482959525577",
          "1-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05---1482959525577"
        ]

        valid_payloads.each do |payload_str|
          payload = TraceContextPayload.from_s payload_str
          assert payload.valid?, "Payload should be valid: '#{payload_str}'"
        end

        invalid_payloads = [
          "-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-1482959525577",
          "1--12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-1482959525577",
          "1-0--6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-1482959525577",
          "1-0-12345--f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-1482959525577",
          "1-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-"
        ]

        invalid_payloads.each do |payload_str|
          payload = TraceContextPayload.from_s payload_str
          refute payload.valid?, "Payload should be invalid: '#{payload_str}'"
        end
      end

      private

      def now_ms
        (Time.now.to_f * 1000).round
      end
    end
  end
end
