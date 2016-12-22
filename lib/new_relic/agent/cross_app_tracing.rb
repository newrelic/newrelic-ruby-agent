# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module CrossAppTracing

      # Exception raised if there is a problem with cross app transactions.
      class Error < RuntimeError; end

      # The cross app response header for "outgoing" calls
      NR_APPDATA_HEADER = 'X-NewRelic-App-Data'

      # The cross app id header for "outgoing" calls
      NR_ID_HEADER = 'X-NewRelic-ID'

      # The cross app transaction header for "outgoing" calls
      NR_TXN_HEADER = 'X-NewRelic-Transaction'

      # The cross app synthetics header
      NR_SYNTHETICS_HEADER = 'X-NewRelic-Synthetics'

      # The index of the transaction GUID in the appdata header of responses
      APPDATA_TXN_GUID_INDEX = 5


      ###############
      module_function
      ###############

      def cross_app_enabled?
        valid_cross_process_id? &&
          valid_encoding_key? &&
          cross_application_tracer_enabled?
      end

      def valid_cross_process_id?
        if NewRelic::Agent.config[:cross_process_id] && NewRelic::Agent.config[:cross_process_id].length > 0
          true
        else
          NewRelic::Agent.logger.debug "No cross_process_id configured"
          false
        end
      end

      def valid_encoding_key?
        if NewRelic::Agent.config[:encoding_key] && NewRelic::Agent.config[:encoding_key].length > 0
          true
        else
          NewRelic::Agent.logger.debug "No encoding_key set"
          false
        end
      end

      def cross_application_tracer_enabled?
        NewRelic::Agent.config[:"cross_application_tracer.enabled"] || NewRelic::Agent.config[:cross_application_tracing]
      end

      def obfuscator
        @obfuscator ||= NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
      end

      # Inject the X-Process header into the outgoing +request+.
      def inject_request_headers(state, request)
        cross_app_id = NewRelic::Agent.config[:cross_process_id]

        state.is_cross_app_caller = true
        txn_guid = state.request_guid
        txn = state.current_transaction
        if txn
          trip_id   = txn.cat_trip_id(state)
          path_hash = txn.cat_path_hash(state)

          if txn.raw_synthetics_header
            request[NR_SYNTHETICS_HEADER] = txn.raw_synthetics_header
          end
        end
        txn_data  = NewRelic::JSONWrapper.dump([txn_guid, false, trip_id, path_hash])

        request[NR_ID_HEADER]  = obfuscator.obfuscate(cross_app_id)
        request[NR_TXN_HEADER] = obfuscator.obfuscate(txn_data)

      rescue NewRelic::Agent::CrossAppTracing::Error => err
        NewRelic::Agent.logger.debug "Not injecting x-process header", err
      end

      def insert_request_headers(request, txn_guid, trip_id, path_hash, synthetics_header)
        cross_app_id = NewRelic::Agent.config[:cross_process_id]
        txn_data  = NewRelic::JSONWrapper.dump([txn_guid, false, trip_id, path_hash])

        request[NR_ID_HEADER]  = obfuscator.obfuscate(cross_app_id)
        request[NR_TXN_HEADER] = obfuscator.obfuscate(txn_data)
        if synthetics_header
          request[NR_SYNTHETICS_HEADER] = synthetics_header
        end
      end

      def add_transaction_trace_parameters(request, response)
        filtered_uri = ::NewRelic::Agent::HTTPClients::URIUtil.filter_uri(request.uri)
        transaction_sampler.add_node_parameters(:uri => filtered_uri)
        if response && response_has_crossapp_header?(response)
          add_cat_transaction_trace_parameters(response)
        end
      end

      # Extract any custom parameters from +response+ if it's cross-application and
      # add them to the current TT node.
      def add_cat_transaction_trace_parameters( response )
        appdata = extract_appdata( response )
        transaction_sampler.add_node_parameters( \
          :transaction_guid => appdata[APPDATA_TXN_GUID_INDEX] )
      end


      # Return the set of metric names that correspond to
      # the given +request+ and +response+.
      # +response+ may be nil in the case that the request produced an error
      # without ever receiving an HTTP response.
      def metrics_for( request, response )
        metrics = common_metrics( request )

        if response && response_has_crossapp_header?( response )
          begin
            metrics.concat metrics_for_crossapp_response( request, response )
          rescue => err
            # Fall back to regular metrics if there's a problem with x-process metrics
            NewRelic::Agent.logger.debug "%p while fetching x-process metrics: %s" %
              [ err.class, err.message ]
            metrics.concat metrics_for_regular_request( request )
          end
        else
          metrics.concat metrics_for_regular_request( request )
        end

        return metrics
      end


      # Return an Array of metrics used for every response.
      def common_metrics( request )
        metrics = [ "External/all" ]
        metrics << "External/#{request.host}/all"

        if NewRelic::Agent::Transaction.recording_web_transaction?
          metrics << "External/allWeb"
        else
          metrics << "External/allOther"
        end

        return metrics
      end

      def response_has_crossapp_header?(response)
        if !!response[NR_APPDATA_HEADER]
          true
        else
          NewRelic::Agent.logger.debug "No #{NR_APPDATA_HEADER} header"
          false
        end
      end


      # Return the set of metric objects appropriate for the given cross app
      # +response+.
      def metrics_for_crossapp_response( request, response )
        xp_id, txn_name, _q_time, _r_time, _req_len, _ = extract_appdata( response )

        raise NewRelic::Agent::CrossAppTracing::Error unless valid_cross_app_id?( xp_id )
        check_transaction_name( txn_name )

        metrics = []
        metrics << "ExternalApp/#{request.host}/#{xp_id}/all"
        metrics << "ExternalTransaction/#{request.host}/#{xp_id}/#{txn_name}"

        return metrics
      end


      # Extract x-process application data from the specified +response+ and return
      # it as an array of the form:
      #
      #  [
      #    <cross app ID>,
      #    <transaction name>,
      #    <queue time in seconds>,
      #    <response time in seconds>,
      #    <request content length in bytes>,
      #    <transaction GUID>
      #  ]
      def extract_appdata(response)
        appdata = response[NR_APPDATA_HEADER]

        decoded_appdata = obfuscator.deobfuscate(appdata)
        decoded_appdata.set_encoding(::Encoding::UTF_8) if
          decoded_appdata.respond_to?(:set_encoding)

        NewRelic::JSONWrapper.load(decoded_appdata)
      end


      # Return the set of metric objects appropriate for the given (non-cross app)
      # +request+.
      def metrics_for_regular_request( request )
        metrics = []
        metrics << "External/#{request.host}/#{request.type}/#{request.method}"

        return metrics
      end


      # Fetch a reference to the stats engine.
      def stats_engine
        NewRelic::Agent.instance.stats_engine
      end

      def transaction_sampler
        NewRelic::Agent.instance.transaction_sampler
      end

      def valid_cross_app_id?(xp_id)
        !!(xp_id =~ /\A\d+#\d+\z/)
      end


      # Check the given +name+ to ensure it conforms to the format of a valid transaction
      # name.
      def check_transaction_name( name )
        # No-op -- apparently absolutely anything is a valid transaction name?
        # This is here for when that inevitably comes back to haunt us.
      end

    end
  end
end
