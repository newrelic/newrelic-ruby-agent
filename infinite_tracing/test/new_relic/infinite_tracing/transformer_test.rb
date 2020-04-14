# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class TransformerTest < Minitest::Test

        def test_transforms_single_span_event
          span_event = Transformer.transform span_event_fixture :single
          assert_kind_of Hash, span_event
          assert_equal "cb4925eee573c1f9c786fdb2b296459b", span_event["trace_id"]
          span_event["intrinsics"].each do |key, value|
            assert_kind_of String, key
            assert_kind_of AttributeValue, value
          end
          assert_empty span_event["user_attributes"]
          assert_empty span_event["agent_attributes"]
        end
        
        def test_transforms_single_full_span_event
          span_event = Transformer.transform span_event_fixture :single_full_attributes
          assert_kind_of Hash, span_event
          assert_equal "cb4925eee573c1f9c786fdb2b296459b", span_event["trace_id"]

          span_event["intrinsics"].each do |key, value|
            assert_kind_of String, key
            assert_kind_of AttributeValue, value
          end

          refute_empty span_event["user_attributes"]
          refute_empty span_event["agent_attributes"]

          span_event["user_attributes"].each do |key, value|
            assert_kind_of String, key
            assert_kind_of AttributeValue, value
          end

          span_event["agent_attributes"].each do |key, value|
            assert_kind_of String, key
            assert_kind_of AttributeValue, value
          end

        end
        
      end
    end
  end
end
