# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module builds the data structures necessary to create a Span
# event for a segment.

require 'new_relic/agent/payload_metric_mapping'
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    module SpanEventPrimitive
      include NewRelic::Coerce
      extend self

      # Strings for static keys of the event structure
      TYPE_KEY           = 'type'.freeze
      TRACE_ID_KEY       = 'traceId'.freeze
      GUID_KEY           = 'guid'.freeze
      PARENT_ID_KEY      = 'parentId'.freeze
      GRANDPARENT_ID_KEY = 'grandparentId'.freeze
      ROOT_SPAN_ID_KEY   = 'rootSpanId'.freeze
      SAMPLED_KEY        = 'sampled'.freeze
      PRIORITY_KEY       = 'priority'.freeze
      TIMESTAMP_KEY      = 'timestamp'.freeze
      DURATION_KEY       = 'duration'.freeze
      NAME_KEY           = 'name'.freeze
      CATEGORY_KEY       = 'category'.freeze

      # Externals
      EXTERNAL_URI_KEY       = "externalUri".freeze
      EXTERNAL_LIBRARY_KEY   = "externalLibrary".freeze
      EXTERNAL_PROCEDURE_KEY = "externalProcedure".freeze

      # Datastores
      DATASTORE_PRODUCT_KEY         = 'datastoreProduct'.freeze
      DATASTORE_COLLECTION_KEY      = 'datastoreCollection'.freeze
      DATASTORE_OPERATION_KEY       = 'datastoreOperation'.freeze
      DATASTORE_HOST_KEY            = 'datastoreHost'.freeze
      DATASTORE_PORT_PATH_OR_ID_KEY = 'datastorePortPathOrId'.freeze
      DATASTORE_NAME_KEY            = 'datastoreName'.freeze

      # Strings for static values of the event structure
      EVENT_TYPE         = 'Span'.freeze
      GENERIC_CATEGORY   = 'generic'.freeze
      EXTERNAL_CATEGORY  = 'external'.freeze
      DATASTORE_CATEGORY = 'datastore'.freeze

      # To avoid allocations when we have empty custom or agent attributes
      EMPTY_HASH = {}.freeze

      def for_segment(segment)
        intrinsics = intrinsics_for(segment)
        intrinsics[CATEGORY_KEY] = GENERIC_CATEGORY

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      def for_external_request_segment(segment)
        intrinsics = intrinsics_for(segment)

        intrinsics[EXTERNAL_URI_KEY]       = segment.uri
        intrinsics[EXTERNAL_LIBRARY_KEY]   = segment.library
        intrinsics[EXTERNAL_PROCEDURE_KEY] = segment.procedure
        intrinsics[CATEGORY_KEY]           = EXTERNAL_CATEGORY

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      def for_datastore_segment(segment)
        intrinsics = intrinsics_for(segment)

        intrinsics[DATASTORE_PRODUCT_KEY]         = segment.product
        intrinsics[DATASTORE_COLLECTION_KEY]      = segment.collection
        intrinsics[DATASTORE_OPERATION_KEY]       = segment.operation
        intrinsics[DATASTORE_HOST_KEY]            = segment.host
        intrinsics[DATASTORE_PORT_PATH_OR_ID_KEY] = segment.port_path_or_id
        intrinsics[DATASTORE_NAME_KEY]            = segment.database_name
        intrinsics[CATEGORY_KEY]                  = DATASTORE_CATEGORY

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      private

      def intrinsics_for(segment)
        {
          TYPE_KEY           => EVENT_TYPE,
          TRACE_ID_KEY       => segment.transaction.trace_id,
          GUID_KEY           => segment.guid,
          PARENT_ID_KEY      => parent_guid(segment),
          GRANDPARENT_ID_KEY => grandparent_guid(segment),
          ROOT_SPAN_ID_KEY   => segment.transaction.guid,
          SAMPLED_KEY        => segment.transaction.sampled?,
          PRIORITY_KEY       => segment.transaction.priority,
          TIMESTAMP_KEY      => milliseconds_since_epoch(segment),
          DURATION_KEY       => segment.duration,
          NAME_KEY           => segment.name
        }
      end

      def parent_guid(segment)
        segment.parent && segment.parent.guid
      end

      def grandparent_guid(segment)
        segment.parent && segment.parent.parent && segment.parent.parent.guid
      end

      def milliseconds_since_epoch(segment)
        Integer(segment.start_time.to_f * 1000.0)
      end
    end
  end
end
