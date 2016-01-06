# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/attribute_filter'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class TransactionEventPrimitiveTest < Minitest::Test
      def setup
        freeze_time
      end

      def test_creates_intrinsics
        intrinsics, *_ = TransactionEventPrimitive.create generate_payload

        assert_equal "Transaction", intrinsics['type']
        assert_in_delta Time.now.to_f, intrinsics['timestamp'], 0.001
        assert_equal "Controller/whatever", intrinsics['name']
        assert_equal false, intrinsics['error']
        assert_equal 0.1, intrinsics['duration']
      end

      def test_event_includes_synthetics
        payload = generate_payload 'whatever',  {
          :synthetics_resource_id=>3,
          :synthetics_job_id=>4,
          :synthetics_monitor_id=>5
        }

        intrinsics, *_ = TransactionEventPrimitive.create payload

        assert_equal '3', intrinsics['nr.syntheticsResourceId']
        assert_equal '4', intrinsics['nr.syntheticsJobId']
        assert_equal '5', intrinsics['nr.syntheticsMonitorId']
      end

      def test_custom_attributes_in_event_are_normalized_to_string_keys
        attributes.merge_custom_attributes(:bing => 2, 1 => 3)
        _, custom_attributes, _ = TransactionEventPrimitive.create generate_payload('whatever')

        assert_equal 2, custom_attributes['bing']
        assert_equal 3, custom_attributes['1']
      end

      def test_agent_attributes_in_event_are_normalized_to_string_keys
        attributes.add_agent_attribute(:yahoo, 7, NewRelic::Agent::AttributeFilter::DST_ALL)
        attributes.add_agent_attribute(4, 2, NewRelic::Agent::AttributeFilter::DST_ALL)
        _, _, agent_attrs = TransactionEventPrimitive.create generate_payload('puce')

        assert_equal 7, agent_attrs[:yahoo]
        assert_equal 2, agent_attrs[4]
      end

      def test_error_is_included_in_event_data
        event_data, *_ = TransactionEventPrimitive.create generate_payload('whatever', :error => true)

        assert event_data['error']
      end

      def test_includes_custom_attributes_in_event
        attributes.merge_custom_attributes('bing' => 2)
        _, custom_attrs, _ = TransactionEventPrimitive.create generate_payload
        assert_equal 2, custom_attrs['bing']
      end

      def test_includes_agent_attributes_in_event
        attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)

        _, _, agent_attrs = TransactionEventPrimitive.create generate_payload
        assert_equal 2, agent_attrs['bing']
      end

      def test_doesnt_include_custom_attributes_in_event_when_configured_not_to
        with_config('transaction_events.attributes.enabled' => false) do
          attributes.merge_custom_attributes('bing' => 2)
          _, custom_attrs, _ = TransactionEventPrimitive.create generate_payload
          assert_empty custom_attrs
        end
      end

      def test_doesnt_include_agent_attributes_in_event_when_configured_not_to
        with_config('transaction_events.attributes.enabled' => false) do
          attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)

          _, _, agent_attrs = TransactionEventPrimitive.create generate_payload
          assert_empty agent_attrs
        end
      end

      def test_doesnt_include_custom_attributes_in_event_when_configured_not_to_with_legacy_setting
        with_config('analytics_events.capture_attributes' => false) do
          attributes.merge_custom_attributes('bing' => 2)

          _, custom_attrs, _ = TransactionEventPrimitive.create generate_payload
          assert_empty custom_attrs
        end
      end

      def test_doesnt_include_agent_attributes_in_event_when_configured_not_to_with_legacy_setting
        with_config('analytics_events.capture_attributes' => false) do
          attributes.add_agent_attribute('bing', 2, NewRelic::Agent::AttributeFilter::DST_ALL)

          _, _, agent_attrs = TransactionEventPrimitive.create generate_payload
          assert_empty agent_attrs
        end
      end

      def test_custom_attributes_in_event_cant_override_reserved_attributes
        metrics = NewRelic::Agent::TransactionMetrics.new()
        metrics.record_unscoped('HttpDispatcher', 0.01)

        attributes.merge_custom_attributes('type' => 'giraffe', 'duration' => 'hippo')
        event, custom_attrs, _ = TransactionEventPrimitive.create generate_payload('whatever', :metrics => metrics)

        assert_equal 'Transaction', event['type']
        assert_equal 0.1, event['duration']

        assert_equal 'giraffe', custom_attrs['type']
        assert_equal 'hippo', custom_attrs['duration']
      end

      def test_samples_on_transaction_finished_event_includes_expected_web_metrics
        txn_metrics = NewRelic::Agent::TransactionMetrics.new
        txn_metrics.record_unscoped('WebFrontend/QueueTime', 13)
        txn_metrics.record_unscoped('External/allWeb',       14)
        txn_metrics.record_unscoped('Datastore/all',         15)
        txn_metrics.record_unscoped("GC/Transaction/all",    16)

        event_data, *_ = TransactionEventPrimitive.create generate_payload('name', :metrics => txn_metrics)
        assert_equal 13, event_data["queueDuration"]
        assert_equal 14, event_data["externalDuration"]
        assert_equal 15, event_data["databaseDuration"]
        assert_equal 16, event_data["gcCumulative"]

        assert_equal 1, event_data["externalCallCount"]
        assert_equal 1, event_data["databaseCallCount"]
      end

      def test_samples_on_transaction_finished_includes_expected_background_metrics
        txn_metrics = NewRelic::Agent::TransactionMetrics.new
        txn_metrics.record_unscoped('External/allOther',  12)
        txn_metrics.record_unscoped('Datastore/all',      13)
        txn_metrics.record_unscoped("GC/Transaction/all", 14)

        event_data, *_ = TransactionEventPrimitive.create generate_payload('name', :metrics => txn_metrics)

        assert_equal 12, event_data["externalDuration"]
        assert_equal 13, event_data["databaseDuration"]
        assert_equal 14, event_data["gcCumulative"]

        assert_equal 1, event_data["databaseCallCount"]
        assert_equal 1, event_data["externalCallCount"]
      end

      def test_samples_on_transaction_finished_event_include_apdex_perf_zone
        event_data, *_ = TransactionEventPrimitive.create generate_payload('name', :apdex_perf_zone => 'S')

        assert_equal 'S', event_data['nr.apdexPerfZone']
      end

      def test_samples_on_transaction_finished_event_includes_guid
        event_data, *_ = TransactionEventPrimitive.create generate_payload('name', :guid => "GUID")
        assert_equal "GUID", event_data["nr.guid"]
      end

      def test_samples_on_transaction_finished_event_includes_referring_transaction_guid
        event_data, *_ = TransactionEventPrimitive.create generate_payload('name', :referring_transaction_guid=> "REFER")
        assert_equal "REFER", event_data["nr.referringTransactionGuid"]
      end

      def generate_payload name = 'whatever', options = {}
        {
          :name => "Controller/#{name}",
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :attributes => attributes,
          :error => false
        }.merge(options)
      end

      def attributes
        @attributes ||= begin
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          NewRelic::Agent::Transaction::Attributes.new(filter)
        end
      end

    end
  end
end
