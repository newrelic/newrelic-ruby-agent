# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'json'
require 'base64'

module NewRelic
  module Agent
    class DistributedTracePayload
      VERSION =[0, 0].freeze
      CALLER_TYPE = "App".freeze
      POUND = '#'.freeze

      # Key names for serialization
      VERSION_KEY             = 'v'.freeze
      DATA_KEY                = 'd'.freeze
      CALLER_TYPE_KEY         = 'ty'.freeze
      CALLER_ACCOUNT_KEY      = 'ac'.freeze
      CALLER_APP_KEY          = 'ap'.freeze
      ID_KEY                  = 'id'.freeze
      TRIP_ID_KEY             = 'tr'.freeze
      SAMPLED_KEY             = 'sa'.freeze
      PARENT_IDS_KEY          = 'pa'.freeze
      TIMESTAMP_KEY           = 'ti'.freeze
      HOST_KEY                = 'ho'.freeze

      # Intrinsic Keys
      CALLER_TYPE_INTRINSIC_KEY                = "caller.type".freeze
      CALLER_APP_INTRINSIC_KEY                 = "caller.app".freeze
      CALLER_ACCOUNT_ID_INTRINSIC_KEY          = "caller.account".freeze
      CALLER_TRANSPORT_TYPE_INTRINSIC_KEY      = "caller.transportType".freeze
      CALLER_TRANSPORT_DURATION_INTRINSIC_KEY  = "caller.transportDuration".freeze
      CALLER_HOST_INTRINSIC_KEY                = "caller.host".freeze
      GUID_INTRINSIC_KEY                       = "nr.guid".freeze
      REFERRING_TRANSACTION_GUID_INTRINSIC_KEY = "nr.referringTransactionGuid".freeze
      TRIP_ID_INTRINSIC_KEY                    = "nr.tripId".freeze
      PARENT_IDS_INTRINSIC_KEY                 = "nr.parentIds".freeze
      COMMA                                    = ",".freeze

      INTRINSIC_KEYS = [
        CALLER_TYPE_INTRINSIC_KEY,
        CALLER_APP_INTRINSIC_KEY,
        CALLER_ACCOUNT_ID_INTRINSIC_KEY,
        CALLER_TRANSPORT_TYPE_INTRINSIC_KEY,
        CALLER_TRANSPORT_DURATION_INTRINSIC_KEY,
        CALLER_HOST_INTRINSIC_KEY,
        GUID_INTRINSIC_KEY,
        REFERRING_TRANSACTION_GUID_INTRINSIC_KEY,
        TRIP_ID_INTRINSIC_KEY,
        PARENT_IDS_INTRINSIC_KEY
      ].freeze

      class << self
        def for_transaction transaction, uri=nil
          payload = new
          return payload unless connected?

          payload.version = VERSION
          payload.caller_type = CALLER_TYPE

          # We should not rely on the xp_id being formulated this way, but we have
          # seen nil account ids coming down in staging for some accounts
          account_id, fallback_app_id = Agent.config[:cross_process_id].split(POUND)
          payload.caller_account_id = account_id

          payload.caller_app_id =  if Agent.config[:application_id].empty?
            fallback_app_id
          else
            Agent.config[:application_id]
          end

          payload.timestamp = (Time.now.to_f * 1000).round
          payload.id = transaction.guid
          payload.trip_id = transaction.distributed_tracing_trip_id
          payload.sampled = transaction.sampled?
          payload.parent_ids = transaction.parent_ids
          payload.host = uri.host if uri

          payload
        end

        def from_json serialized_payload
          raw_payload = JSON.parse serialized_payload
          payload_data = raw_payload[DATA_KEY]

          payload = new
          payload.version           = raw_payload[VERSION_KEY]
          payload.caller_type       = payload_data[CALLER_TYPE_KEY]
          payload.caller_account_id = payload_data[CALLER_ACCOUNT_KEY]
          payload.caller_app_id     = payload_data[CALLER_APP_KEY]
          payload.timestamp         = payload_data[TIMESTAMP_KEY]
          payload.id                = payload_data[ID_KEY]
          payload.trip_id           = payload_data[TRIP_ID_KEY]
          payload.sampled           = payload_data[SAMPLED_KEY]
          payload.parent_ids        = payload_data[PARENT_IDS_KEY]
          payload.host              = payload_data[HOST_KEY]

          payload
        end

        def from_http_safe http_safe_payload
          decoded_payload = Base64.strict_decode64 http_safe_payload
          from_json decoded_payload
        end

        #assigns intrinsics for the first distributed trace in a trip
        def assign_initial_intrinsics transaction, payload
          payload[TRIP_ID_INTRINSIC_KEY] = transaction.distributed_tracing_trip_id
          payload[PARENT_IDS_INTRINSIC_KEY] = transaction.parent_ids
        end

        private

        # We use the presence of the cross_process_id in the config to tell if we
        # have connected yet.
        def connected?
          !!Agent.config[:'cross_process_id']
        end
      end

      attr_accessor :version,
                    :caller_type,
                    :caller_transport_type,
                    :caller_account_id,
                    :caller_app_id,
                    :id,
                    :trip_id,
                    :sampled,
                    :parent_ids,
                    :timestamp,
                    :host

      alias_method :sampled?, :sampled

      def to_json
        result = {
          VERSION_KEY => version
        }

        result[DATA_KEY] = {
          CALLER_TYPE_KEY    => caller_type,
          CALLER_ACCOUNT_KEY => caller_account_id,
          CALLER_APP_KEY     => caller_app_id,
          ID_KEY             => id,
          TRIP_ID_KEY        => trip_id,
          SAMPLED_KEY        => sampled,
          PARENT_IDS_KEY     => parent_ids,
          HOST_KEY           => host,
          TIMESTAMP_KEY      => timestamp,
        }

        JSON.dump(result)
      end

      alias_method :text, :to_json

      def http_safe
        Base64.strict_encode64 to_json
      end

      def assign_intrinsics transaction, payload
        payload[CALLER_TYPE_INTRINSIC_KEY] = caller_type
        payload[CALLER_APP_INTRINSIC_KEY] = caller_app_id
        payload[CALLER_ACCOUNT_ID_INTRINSIC_KEY] = caller_account_id
        payload[CALLER_TRANSPORT_TYPE_INTRINSIC_KEY] = caller_transport_type
        payload[CALLER_TRANSPORT_DURATION_INTRINSIC_KEY] = transaction.transport_duration
        payload[CALLER_HOST_INTRINSIC_KEY] = host
        payload[GUID_INTRINSIC_KEY] = transaction.guid
        payload[REFERRING_TRANSACTION_GUID_INTRINSIC_KEY] = id
        payload[TRIP_ID_INTRINSIC_KEY] = trip_id
        payload[PARENT_IDS_INTRINSIC_KEY] = parent_ids.join COMMA if parent_ids
      end
    end
  end
end
