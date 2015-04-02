# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..','..','test_helper'))
require 'new_relic/agent/transaction/intrinsic_attributes'
require 'new_relic/agent/attribute_filter'

class NewRelic::Agent::Transaction
  class IntrinsicAttributesTest < Minitest::Test
    def setup
      @config = { :'attributes.enabled' => false }
      NewRelic::Agent.config.add_config_for_testing(@config)
      NewRelic::Agent.instance.refresh_attribute_filter

      @attributes = IntrinsicAttributes.new(NewRelic::Agent.instance.attribute_filter)
      @attributes.add(:see, "me")
    end

    def teardown
      NewRelic::Agent.config.remove_config(@config)
      NewRelic::Agent.instance.refresh_attribute_filter
    end

    def test_allows_transaction_tracer
      assert_sees_attributes(@attributes, NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER)
    end

    def test_allows_error_collector
      assert_sees_attributes(@attributes, NewRelic::Agent::AttributeFilter::DST_ERROR_COLLECTOR)
    end

    def test_disallows_transaction_events
      refute_sees_attributes(@attributes, NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS)
    end

    def test_disallows_browser_monitoring
      refute_sees_attributes(@attributes, NewRelic::Agent::AttributeFilter::DST_BROWSER_MONITORING)
    end

    def refute_sees_attributes(attributes, destination)
      result = attributes.for_destination(destination)
      assert_empty result
    end

    def assert_sees_attributes(attributes, destination)
      result = attributes.for_destination(destination)
      refute_empty result
    end
  end
end
