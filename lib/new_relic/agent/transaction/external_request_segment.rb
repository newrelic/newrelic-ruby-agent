# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/http_clients/uri_util'

module NewRelic
  module Agent
    class Transaction
      class ExternalRequestSegment < Segment
        attr_reader :library, :uri, :procedure

        def initialize library, uri, procedure
          @library = library
          @uri = normalize_uri uri
          @procedure = procedure
          super()
        end

        def name
          @name ||= "External/#{host}/#{library}/#{procedure}"
        end

        def host
          uri.host
        end

        def add_request_headers request
          unless CrossAppTracing.cross_app_enabled?
            NewRelic::Agent.logger.debug "Not injecting x-process header"
            return
          end

          transaction_state.is_cross_app_caller = true
          txn_guid = transaction_state.request_guid
          trip_id   = transaction && transaction.cat_trip_id(transaction_state)
          path_hash = transaction && transaction.cat_path_hash(transaction_state)
          synthetics_header = transaction && transaction.raw_synthetics_header

          CrossAppTracing.insert_request_headers request, txn_guid, trip_id, path_hash, synthetics_header
        rescue => e
          NewRelic::Agent.logger.error "Error in add_request_headers", e
        end


        private

        def normalize_uri uri
          uri.is_a?(URI) ? uri : HTTPClients::URIUtil.parse_url(uri)
        end

        EXTERNAL_ALL = "External/all".freeze

        def unscoped_metrics
          [
            EXTERNAL_ALL,
            "External/#{host}/all",
            suffixed_rollup_metric
          ]
        end

        EXTERNAL_ALL_WEB = "External/allWeb".freeze
        EXTERNAL_ALL_OTHER = "External/allOther".freeze

        def suffixed_rollup_metric
          if Transaction.recording_web_transaction?
            EXTERNAL_ALL_WEB
          else
            EXTERNAL_ALL_OTHER
          end
        end
      end
    end
  end
end
