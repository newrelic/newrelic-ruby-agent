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
          @host_header = nil
          @app_data = nil
          super()
        end

        def name
          @name ||= "External/#{host}/#{library}/#{procedure}"
        end

        def host
          @host_header || uri.host
        end

        # This method will add NewRelic headers for cross application tracing and
        # will check to see if a host header is used for the request. If a host
        # header is used it will update the segment name to reflect the host header.
        def add_request_headers request
          process_host_header request
          unless CrossAppTracing.cross_app_enabled?
            NewRelic::Agent.logger.debug "Unable to add_request_headers from external segment"
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

        def read_response_headers response
          unless CrossAppTracing.cross_app_enabled?
            NewRelic::Agent.logger.debug "Unable to read_response_headers from external segment"
            return
          end
          return unless CrossAppTracing.response_has_crossapp_header?(response)
          unless data = CrossAppTracing.extract_appdata(response)
            NewRelic::Agent.logger.debug "Couldn't extract_appdata from external segment response"
            return
          end

          if CrossAppTracing.valid_cross_app_id?(data[0])
            @app_data = data
            update_segment_name
          else
            NewRelic::Agent.logger.debug "External segment response has invalid cross_app_id"
          end
        rescue => e
          NewRelic::Agent.logger.error "Error in read_response_headers", e
        end

        def cross_app_request?
          !!@app_data
        end

        def cross_process_id
          @app_data && @app_data[0]
        end

        def transaction_guid
          @app_data && @app_data[5]
        end

        def cross_process_transaction_name
          @app_data && @app_data[1]
        end

        private

        def segment_complete
          node_params = {:uri => HTTPClients::URIUtil.filter_uri(uri)}
          if cross_app_request?
            node_params[:transaction_guid] = transaction_guid
          end
          Agent.instance.transaction_sampler.add_node_parameters node_params
        end

        def normalize_uri uri
          uri.is_a?(URI) ? uri : HTTPClients::URIUtil.parse_url(uri)
        end

        def process_host_header request
          if @host_header = request.host_from_header
            update_segment_name
          end
        end

        EXTERNAL_ALL = "External/all".freeze

        def unscoped_metrics
          metrics = [ EXTERNAL_ALL,
            "External/#{host}/all",
            suffixed_rollup_metric
          ]

          if cross_app_request?
            metrics << "ExternalApp/#{host}/#{cross_process_id}/all"
          end

          metrics
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

        def update_segment_name
          if @app_data
            @name = "ExternalTransaction/#{host}/#{cross_process_id}/#{cross_process_transaction_name}"
          else
            @name = "External/#{host}/#{library}/#{procedure}"
          end
        end
      end
    end
  end
end
