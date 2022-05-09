# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'
require 'new_relic/agent/linking_metadata'

module NewRelic::Agent
  module LinkingMetadata
    class LinkingMetadataTest < Minitest::Test
      def setup
        @config = nil
        Hostname.stubs(:get).returns("localhost")
        reset_buffers_and_caches
      end

      def teardown
        NewRelic::Agent.config.remove_config(@config) if @config
        NewRelic::Agent.config.reset_to_defaults
        reset_buffers_and_caches
      end

      def test_service_metadata_requires_hash
        assert_raises(ArgumentError) do
          LinkingMetadata.append_service_linking_metadata(nil)
        end
      end

      def test_service_metadata_without_guid
        apply_config({
          :app_name => ["Test app", "Another name"]
        })

        result = Hash.new
        LinkingMetadata.append_service_linking_metadata(result)

        expected = {
          "entity.name" => "Test app",
          "entity.type" => "SERVICE",
          "hostname" => "localhost"
        }
        assert_equal(expected, result)
      end

      def test_service_metadata_with_guid
        apply_config({
          :app_name => ["Test app", "Another name"],
          :entity_guid => "GUID"
        })

        result = Hash.new
        LinkingMetadata.append_service_linking_metadata(result)

        expected = {
          "entity.guid" => "GUID",
          "entity.name" => "Test app",
          "entity.type" => "SERVICE",
          "hostname" => "localhost"
        }
        assert_equal(expected, result)
      end

      def test_trace_metadata_empty
        assert_raises(ArgumentError) do
          LinkingMetadata.append_trace_linking_metadata(nil)
        end
      end

      def test_trace_metadata_empty
        result = Hash.new
        LinkingMetadata.append_trace_linking_metadata(result)
        assert_empty(result)
      end

      def test_trace_metadata_with_ids
        Tracer.stubs(:current_trace_id).returns("trace_id")
        Tracer.stubs(:current_span_id).returns("span_id")

        result = Hash.new
        LinkingMetadata.append_trace_linking_metadata(result)

        expected = {
          "trace.id" => "trace_id",
          "span.id" => "span_id"
        }
        assert_equal(expected, result)
      end

      def apply_config(config)
        @config = config
        NewRelic::Agent.config.add_config_for_testing(@config)
      end
    end
  end
end
