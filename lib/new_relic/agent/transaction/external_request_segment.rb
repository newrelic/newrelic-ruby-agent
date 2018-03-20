# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/http_clients/uri_util'

module NewRelic
  module Agent
    class Transaction

      #
      # This class represents an external segment in a transaction trace.
      #
      # @api public
      class ExternalRequestSegment < Segment
        attr_reader :library, :uri, :procedure

        NR_SYNTHETICS_HEADER = 'X-NewRelic-Synthetics'.freeze


        def initialize library, uri, procedure, start_time = nil # :nodoc:
          @library = library
          @uri = HTTPClients::URIUtil.parse_and_normalize_url(uri)
          @procedure = procedure
          @host_header = nil
          @app_data = nil
          super(nil, nil, start_time)
        end

        def name # :nodoc:
          @name ||= "External/#{host}/#{library}/#{procedure}"
        end

        def host # :nodoc:
          @host_header || uri.host
        end

        # This method adds New Relic request headers to a given request made to an
        # external API and checks to see if a host header is used for the request.
        # If a host header is used, it updates the segment name to match the host
        # header.
        #
        # @param [NewRelic::Agent::HTTPClients::AbstractRequest] request the request
        # object (must belong to a subclass of NewRelic::Agent::HTTPClients::AbstractRequest)
        #
        # @api public
        def add_request_headers request
          process_host_header request
          synthetics_header = transaction && transaction.raw_synthetics_header
          insert_synthetics_header request, synthetics_header if synthetics_header

          return unless record_metrics?

          insert_cross_app_header         request
          insert_distributed_trace_header request
        rescue => e
          NewRelic::Agent.logger.error "Error in add_request_headers", e
        end

        # This method extracts app data from an external response if present. If
        # a valid cross-app ID is found, the name of the segment is updated to
        # reflect the cross-process ID and transaction name.
        #
        # @param [Hash] response a hash of response headers
        #
        # @api public
        def read_response_headers response
          return unless record_metrics? && CrossAppTracing.cross_app_enabled?
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

        def cross_app_request? # :nodoc:
          !!@app_data
        end

        def cross_process_id # :nodoc:
          @app_data && @app_data[0]
        end

        def transaction_guid # :nodoc:
          @app_data && @app_data[5]
        end

        def cross_process_transaction_name # :nodoc:
          @app_data && @app_data[1]
        end

        EXTERNAL_TRANSACTION_PREFIX = 'ExternalTransaction/'.freeze
        SLASH = '/'.freeze
        APP_DATA_KEY = 'NewRelicAppData'.freeze

        # Obtain an obfuscated +String+ suitable for delivery across public networks that identifies this application
        # and transaction to another application which is also running a New Relic agent. This +String+ can be processed
        # by +process_request_metadata+ on the receiving application.
        #
        # @return [String] obfuscated request metadata to send
        #
        # @api public
        #
        def get_request_metadata
          NewRelic::Agent.record_api_supportability_metric(:get_request_metadata)
          return unless CrossAppTracing.cross_app_enabled?

          if transaction

            # build hash of CAT metadata
            #
            rmd = {
              NewRelicID: NewRelic::Agent.config[:cross_process_id],
              NewRelicTransaction: [
                transaction.guid,
                false,
                transaction.cat_trip_id,
                transaction.cat_path_hash
              ]
            }

            # flag cross app in the state so transaction knows to add bits to paylaod
            #
            transaction.state.is_cross_app_caller = true

            # add Synthetics header if we have it
            #
            rmd[:NewRelicSynthetics] = transaction.raw_synthetics_header if transaction.raw_synthetics_header

            # obfuscate the generated request metadata JSON
            #
            obfuscator.obfuscate ::JSON.dump(rmd)

          end
        rescue => e
          NewRelic::Agent.logger.error "error during get_request_metadata", e
        end

        # Process obfuscated +String+ sent from a called application that is also running a New Relic agent and
        # save information in current transaction for inclusion in a trace. This +String+ is generated by
        # +get_response_metadata+ on the receiving application.
        #
        # @param response_metadata [String] received obfuscated response metadata
        #
        # @api public
        #
        def process_response_metadata response_metadata
          NewRelic::Agent.record_api_supportability_metric(:process_response_metadata)
          if transaction
            app_data = ::JSON.parse(obfuscator.deobfuscate(response_metadata))[APP_DATA_KEY]

            # validate cross app id
            #
            if Array === app_data and CrossAppTracing.trusted_valid_cross_app_id? app_data[0]
              @app_data = app_data
              update_segment_name
            else
              NewRelic::Agent.logger.error "error processing response metadata: invalid/non-trusted ID"
            end
          end

          nil
        rescue => e
          NewRelic::Agent.logger.error "error during process_response_metadata", e
        end

        def record_metrics
          add_unscoped_metrics
          record_distributed_tracing_metrics if Agent.config[:'distributed_tracing.enabled']
          super
        end

        private

        def insert_synthetics_header request, header
          request[NR_SYNTHETICS_HEADER] = header
        end

        def segment_complete
          params[:uri] = HTTPClients::URIUtil.filter_uri(uri)
          if cross_app_request?
            params[:transaction_guid] = transaction_guid
          end

          super
        end

        def process_host_header request
          if @host_header = request.host_from_header
            update_segment_name
          end
        end

        def insert_cross_app_header request
          return unless CrossAppTracing.cross_app_enabled?

          transaction_state.is_cross_app_caller = true
          txn_guid = transaction_state.request_guid
          trip_id   = transaction && transaction.cat_trip_id
          path_hash = transaction && transaction.cat_path_hash

          CrossAppTracing.insert_request_headers request, txn_guid, trip_id, path_hash
        end

        X_NEWRELIC_TRACE_HEADER = "X-NewRelic-Trace".freeze

        def insert_distributed_trace_header request
          return unless Agent.config[:'distributed_tracing.enabled']
          payload = transaction.create_distributed_trace_payload
          request[X_NEWRELIC_TRACE_HEADER] = payload.http_safe
        end

        EXTERNAL_ALL = "External/all".freeze

        def add_unscoped_metrics
          @unscoped_metrics = [ EXTERNAL_ALL,
            "External/#{host}/all",
            suffixed_rollup_metric
          ]

          if cross_app_request?
            @unscoped_metrics << "ExternalApp/#{host}/#{cross_process_id}/all"
          end
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

        ALL_SUFFIX = "all".freeze
        ALL_WEB_SUFFIX = "allWeb".freeze
        ALL_OTHER_SUFFIX = "allOther".freeze

        def transaction_type_suffix
          if Transaction.recording_web_transaction?
            ALL_WEB_SUFFIX
          else
            ALL_OTHER_SUFFIX
          end
        end

        def record_distributed_tracing_metrics
          add_caller_by_duration_metrics
          record_transport_duration_metrics
          record_errors_by_caller_metrics
        end

        DURATION_BY_CALLER_UNKOWN_PREFIX = "DurationByCaller/Unknown/Unknown/Unknown/Unknown".freeze

        def add_caller_by_duration_metrics
          prefix = if transaction.distributed_trace?
            payload = transaction.distributed_trace_payload
            "DurationByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/transport"
          else
            DURATION_BY_CALLER_UNKOWN_PREFIX
          end

          @unscoped_metrics << "#{prefix}/#{ALL_SUFFIX}"
          @unscoped_metrics << "#{prefix}/#{transaction_type_suffix}"
        end

        def record_transport_duration_metrics
          return unless transaction.distributed_trace?
          payload = transaction.distributed_trace_payload
          prefix = "TransportDuration/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/transport"
          metric_cache.record_unscoped "#{prefix}/#{ALL_SUFFIX}", transaction.transport_duration
          metric_cache.record_unscoped "#{prefix}/#{transaction_type_suffix}", transaction.transport_duration
        end

        ERRORS_BY_CALLER_UNKOWN_PREFIX = "ErrorsByCaller/Unknown/Unknown/Unknown/Unknown".freeze

        def record_errors_by_caller_metrics
          return unless transaction.exceptions.size > 0
          prefix = if transaction.distributed_trace?
            payload = transaction.distributed_trace_payload
            "ErrorsByCaller/#{payload.parent_type}/#{payload.parent_account_id}/#{payload.parent_app_id}/transport"
          else
            ERRORS_BY_CALLER_UNKOWN_PREFIX
          end

          NewRelic::Agent.increment_metric "#{prefix}/#{ALL_SUFFIX}"
          NewRelic::Agent.increment_metric "#{prefix}/#{transaction_type_suffix}"
        end

        def update_segment_name
          if @app_data
            @name = "ExternalTransaction/#{host}/#{cross_process_id}/#{cross_process_transaction_name}"
          else
            @name = "External/#{host}/#{library}/#{procedure}"
          end
        end

        def obfuscator
          CrossAppTracing.obfuscator
        end
      end
    end
  end
end
