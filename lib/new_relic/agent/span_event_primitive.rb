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
      TYPE_KEY                = 'type'.freeze
      TRACE_ID_KEY            = 'traceId'.freeze
      GUID_KEY                = 'guid'.freeze
      PARENT_ID_KEY           = 'parentId'.freeze
      GRANDPARENT_ID_KEY      = 'grandparentId'.freeze
      APP_LOCAL_ROOT_ID_KEY   = 'appLocalRootId'.freeze
      SAMPLED_KEY             = 'sampled'.freeze
      PRIORITY_KEY            = 'priority'.freeze
      TIMESTAMP_KEY           = 'timestamp'.freeze
      DURATION_KEY            = 'duration'.freeze
      NAME_KEY                = 'name'.freeze
      CATEGORY_KEY            = 'category'.freeze
      HTTP_URL_KEY            = 'http.url'.freeze
      HTTP_METHOD_KEY         = 'http.method'.freeze
      COMPONENT_KEY           = 'component'.freeze
      DB_INSTANCE_KEY         = 'db.instance'.freeze
      DB_STATEMENT_KEY        = 'db.statement'.freeze
      PEER_ADDRESS_KEY        = 'peer.address'.freeze
      PEER_HOSTNAME_KEY       = 'peer.hostname'.freeze
      SPAN_KIND_KEY           = 'span.kind'.freeze

      # Strings for static values of the event structure
      EVENT_TYPE         = 'Span'.freeze
      GENERIC_CATEGORY   = 'generic'.freeze
      HTTP_CATEGORY      = 'http'.freeze
      DATASTORE_CATEGORY = 'datastore'.freeze
      CLIENT             = 'client'.freeze

      # To avoid allocations when we have empty custom or agent attributes
      EMPTY_HASH = {}.freeze

      def for_segment(segment)
        intrinsics = intrinsics_for(segment)
        intrinsics[CATEGORY_KEY] = GENERIC_CATEGORY

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      def for_external_request_segment(segment)
        intrinsics = intrinsics_for(segment)

        intrinsics[HTTP_URL_KEY]       = segment.uri
        intrinsics[COMPONENT_KEY] = segment.library
        intrinsics[HTTP_METHOD_KEY]    = segment.procedure
        intrinsics[CATEGORY_KEY]  = HTTP_CATEGORY
        intrinsics[SPAN_KIND_KEY] = CLIENT

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      def for_datastore_segment(segment)
        intrinsics = intrinsics_for(segment)

        intrinsics[COMPONENT_KEY]     = segment.product
        intrinsics[DB_INSTANCE_KEY]   = segment.database_name
        intrinsics[PEER_ADDRESS_KEY]  = "#{segment.host}:#{segment.port_path_or_id}"
        intrinsics[PEER_HOSTNAME_KEY] = segment.host
        intrinsics[SPAN_KIND_KEY]     = CLIENT
        intrinsics[CATEGORY_KEY]      = DATASTORE_CATEGORY

        if segment.sql_statement
          intrinsics[DB_STATEMENT_KEY] = segment.sql_statement.safe_sql
        elsif segment.nosql_statement
          intrinsics[DB_STATEMENT_KEY] = segment.nosql_statement
        end

        [intrinsics, EMPTY_HASH, EMPTY_HASH]
      end

      private

      def intrinsics_for(segment)
        {
          TYPE_KEY                => EVENT_TYPE,
          TRACE_ID_KEY            => segment.transaction.trace_id,
          GUID_KEY                => segment.guid,
          PARENT_ID_KEY           => parent_guid(segment),
          APP_LOCAL_ROOT_ID_KEY   => segment.transaction.guid,
          SAMPLED_KEY             => segment.transaction.sampled?,
          PRIORITY_KEY            => segment.transaction.priority,
          TIMESTAMP_KEY           => milliseconds_since_epoch(segment),
          DURATION_KEY            => segment.duration,
          NAME_KEY                => segment.name
        }
      end

      def parent_guid(segment)
        segment.parent && segment.parent.guid
      end

      def milliseconds_since_epoch(segment)
        Integer(segment.start_time.to_f * 1000.0)
      end
    end
  end
end
