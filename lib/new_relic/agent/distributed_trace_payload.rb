# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'json'
require 'base64'

module NewRelic
  module Agent
    class DistributedTracePayload
      VERSION =[0, 1].freeze
      PARENT_TYPE = "App".freeze
      POUND = '#'.freeze

      # Key names for serialization
      VERSION_KEY                = 'v'.freeze
      DATA_KEY                   = 'd'.freeze
      PARENT_TYPE_KEY            = 'ty'.freeze
      PARENT_ACCOUNT_ID_KEY      = 'ac'.freeze
      PARENT_APP_KEY             = 'ap'.freeze
      ID_KEY                     = 'id'.freeze
      TRACE_ID_KEY               = 'tr'.freeze
      SAMPLED_KEY                = 'sa'.freeze
      PARENT_ID_KEY              = 'pa'.freeze
      TIMESTAMP_KEY              = 'ti'.freeze
      PRIORITY_KEY               = 'pr'.freeze

      # Intrinsic Keys
      PARENT_TYPE_INTRINSIC_KEY                = "parent.type".freeze
      PARENT_APP_INTRINSIC_KEY                 = "parent.app".freeze
      PARENT_ACCOUNT_ID_INTRINSIC_KEY          = "parent.account".freeze
      PARENT_TRANSPORT_TYPE_INTRINSIC_KEY      = "parent.transportType".freeze
      PARENT_TRANSPORT_DURATION_INTRINSIC_KEY  = "parent.transportDuration".freeze
      GUID_INTRINSIC_KEY                       = "guid".freeze
      TRACE_ID_INTRINSIC_KEY                   = "traceId".freeze
      TRIP_ID_INTRINSIC_KEY                    = "nr.tripId".freeze
      PARENT_ID_INTRINSIC_KEY                  = "parentId".freeze
      GRANDPARENT_ID_INTRINSIC_KEY             = "grandparentId".freeze
      COMMA                                    = ",".freeze

      INTRINSIC_KEYS = [
        PARENT_TYPE_INTRINSIC_KEY,
        PARENT_APP_INTRINSIC_KEY,
        PARENT_ACCOUNT_ID_INTRINSIC_KEY,
        PARENT_TRANSPORT_TYPE_INTRINSIC_KEY,
        PARENT_TRANSPORT_DURATION_INTRINSIC_KEY,
        GUID_INTRINSIC_KEY,
        TRACE_ID_INTRINSIC_KEY,
        TRIP_ID_INTRINSIC_KEY,
        PARENT_ID_INTRINSIC_KEY,
        GRANDPARENT_ID_INTRINSIC_KEY
      ].freeze

      # Intrinsic Values
      PARENT_TRANSPORT_TYPE_UNKNOWN = 'unknown'.freeze

      class << self
        def for_transaction transaction
          payload = new
          return payload unless connected?

          payload.version = VERSION
          payload.parent_type = PARENT_TYPE

          # We should not rely on the xp_id being formulated this way, but we have
          # seen nil account ids coming down in staging for some accounts
          account_id, fallback_app_id = Agent.config[:cross_process_id].split(POUND)
          payload.parent_account_id = account_id

          payload.parent_app_id =  if Agent.config[:application_id].empty?
            fallback_app_id
          else
            Agent.config[:application_id]
          end

          payload.timestamp = (Time.now.to_f * 1000).round
          payload.id = transaction.guid
          payload.trace_id = transaction.trace_id
          payload.sampled = transaction.sampled?
          payload.priority = transaction.priority
          payload.parent_id = transaction.parent_id
          payload.grandparent_id = transaction.grandparent_id

          payload
        end

        def from_json serialized_payload
          raw_payload = JSON.parse serialized_payload
          payload_data = raw_payload[DATA_KEY]

          payload = new
          payload.version           = raw_payload[VERSION_KEY]
          payload.parent_type       = payload_data[PARENT_TYPE_KEY]
          payload.parent_account_id = payload_data[PARENT_ACCOUNT_ID_KEY]
          payload.parent_app_id     = payload_data[PARENT_APP_KEY]
          payload.timestamp         = payload_data[TIMESTAMP_KEY]
          payload.id                = payload_data[ID_KEY]
          payload.trace_id          = payload_data[TRACE_ID_KEY]
          payload.sampled           = payload_data[SAMPLED_KEY]
          payload.priority          = payload_data[PRIORITY_KEY]
          payload.parent_id         = payload_data[ID_KEY]        # Our parent ID is the caller's GUID
          payload.grandparent_id    = payload_data[PARENT_ID_KEY] # Our grandparent ID is the caller's parent ID

          payload
        end

        def from_http_safe http_safe_payload
          decoded_payload = Base64.strict_decode64 http_safe_payload
          from_json decoded_payload
        end

        # Assigns intrinsics for the first distributed trace in a trip
        def assign_intrinsics_for_first_trace transaction, transaction_payload
          transaction_payload[GUID_INTRINSIC_KEY] = transaction.guid
          transaction_payload[TRACE_ID_INTRINSIC_KEY] = transaction.trace_id
          transaction_payload[TRIP_ID_INTRINSIC_KEY]  = transaction.trace_id
        end

        def major_version_matches?(payload)
          payload.version[0] == VERSION[0]
        end

        private

        # We use the presence of the cross_process_id in the config to tell if we
        # have connected yet.
        def connected?
          !!Agent.config[:'cross_process_id']
        end
      end

      attr_accessor :version,
                    :parent_type,
                    :caller_transport_type,
                    :parent_account_id,
                    :parent_app_id,
                    :id,
                    :trace_id,
                    :sampled,
                    :priority,
                    :parent_id,
                    :grandparent_id,
                    :timestamp

      alias_method :sampled?, :sampled

      def initialize
        @caller_transport_type = PARENT_TRANSPORT_TYPE_UNKNOWN
      end

      def to_json
        result = {
          VERSION_KEY => version
        }

        result[DATA_KEY] = {
          PARENT_TYPE_KEY       => parent_type,
          PARENT_ACCOUNT_ID_KEY => parent_account_id,
          PARENT_APP_KEY        => parent_app_id,
          ID_KEY                => id,
          TRACE_ID_KEY          => trace_id,
          SAMPLED_KEY           => sampled,
          PRIORITY_KEY          => priority,
          PARENT_ID_KEY         => parent_id,
          # GRANDPARENT_ID_KEY does not go into the outbound JSON payload;
          # the callee will take our parent ID as its grandparent ID
          TIMESTAMP_KEY      => timestamp,
        }

        JSON.dump(result)
      end

      alias_method :text, :to_json

      def http_safe
        Base64.strict_encode64 to_json
      end

      def assign_intrinsics transaction, transaction_payload
        transaction_payload[PARENT_TYPE_INTRINSIC_KEY] = parent_type
        transaction_payload[PARENT_APP_INTRINSIC_KEY] = parent_app_id
        transaction_payload[PARENT_ACCOUNT_ID_INTRINSIC_KEY] = parent_account_id
        transaction_payload[PARENT_TRANSPORT_TYPE_INTRINSIC_KEY] = caller_transport_type
        transaction_payload[PARENT_TRANSPORT_DURATION_INTRINSIC_KEY] = transaction.transport_duration
        transaction_payload[GUID_INTRINSIC_KEY] = transaction.guid
        transaction_payload[TRACE_ID_INTRINSIC_KEY] = trace_id
        transaction_payload[TRIP_ID_INTRINSIC_KEY] = trace_id
        transaction_payload[PARENT_ID_INTRINSIC_KEY] = parent_id if parent_id
        transaction_payload[GRANDPARENT_ID_INTRINSIC_KEY] = grandparent_id if grandparent_id
      end
    end
  end
end
