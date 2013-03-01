# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module CrossAppTracing
      extend NewRelic::Agent::CrossAppMonitor::EncodingFunctions

      # Exception raised if there is a problem with cross app transactions.
      class Error < RuntimeError; end


      # The cross app response header for "outgoing" calls
      NR_APPDATA_HEADER = 'X-NewRelic-App-Data'

      # The cross app id header for "outgoing" calls
      NR_ID_HEADER = 'X-NewRelic-ID'

      # The cross app transaction header for "outgoing" calls
      NR_TXN_HEADER = 'X-NewRelic-Transaction'

      # The index of the transaction GUID in the appdata header of responses
      APPDATA_TXN_GUID_INDEX = 5


      ###############
      module_function
      ###############

      # Send the given +request+, adding metrics appropriate to the
      # response when it comes back.
      def trace_http_request( http, request )
        return yield unless NewRelic::Agent.is_execution_traced?

        t0, segment = start_trace( http, request )
        begin
          response = yield
        ensure
          finish_trace( t0, segment, request, response, http ) if t0
        end

        return response
      end


      # Set up the necessary state for cross-application tracing before the
      # given +request+ goes out on the specified +http+ connection.
      def start_trace( http, request )
        inject_request_headers( request ) if cross_app_enabled?

        # Create a segment and time the call
        t0 = Time.now
        segment = stats_engine.push_scope( "External/#{http.address}/all", t0 )

        return t0, segment
      rescue => err
        NewRelic::Agent.logger.error "Uncaught exception while tracing HTTP request", err
        return nil
      end


      # Finish tracing the HTTP +request+ that started at +t0+ with the information in
      # +response+ and the given +http+ connection.
      def finish_trace( t0, segment, request, response, http )
        t1 = Time.now
        duration = t1.to_f - t0.to_f

        begin
          if request && response && http
            # Figure out which metrics we need to report based on the request and response
            # The last (most-specific) one is scoped.
            metrics = metrics_for( http, request, response )
            scoped_metric = metrics.pop

            stats_engine.record_metrics(metrics, duration)
            stats_engine.record_metrics(scoped_metric, duration, :scoped => true)

            # Add TT custom parameters
            stats_engine.rename_scope_segment( scoped_metric )
            extract_custom_parameters( response ) if response_is_crossapp?( response )
          end
        ensure
          # We always need to pop the scope stack to avoid an inconsistent
          # state, which will prevent tracing of the whole transaction.
          stats_engine.pop_scope( segment, duration, t1 )
        end
      rescue NewRelic::Agent::CrossAppTracing::Error => err
        NewRelic::Agent.logger.debug "while cross app tracing", err
      rescue => err
        NewRelic::Agent.logger.error "Uncaught exception while finishing an HTTP request trace", err
      end


      # Return +true+ if cross app tracing is enabled in the config.
      def cross_app_enabled?
        NewRelic::Agent.config[:cross_process_id] &&
          (NewRelic::Agent.config[:"cross_application_tracer.enabled"] ||
           NewRelic::Agent.config[:cross_application_tracing])
      end


      # Memoized fetcher for the cross app encoding key. Raises a
      # NewRelic::Agent::CrossAppTracing::Error if the key isn't configured.
      def cross_app_encoding_key
        NewRelic::Agent.config[:encoding_key] or
          raise NewRelic::Agent::CrossAppTracing::Error, "No encoding_key set."
      end


      # Inject the X-Process header into the outgoing +request+.
      def inject_request_headers( request )
        key = cross_app_encoding_key()
        cross_app_id = NewRelic::Agent.config[:cross_process_id] or
          raise NewRelic::Agent::CrossAppTracing::Error, "no cross app ID configured"
        txn_guid = NewRelic::Agent::TransactionInfo.get.guid
        txn_data = NewRelic.json_dump([ txn_guid, false ])

        request[ NR_ID_HEADER ] = obfuscate_with_key( key, cross_app_id )
        request[ NR_TXN_HEADER ] = obfuscate_with_key( key, txn_data )

      rescue NewRelic::Agent::CrossAppTracing::Error => err
        NewRelic::Agent.logger.debug "Not injecting x-process header", err
      end


      # Extract any custom parameters from +response+ if it's cross-application and
      # add them to the current TT node.
      def extract_custom_parameters( response )

        appdata = extract_appdata( response )
        sampler = NewRelic::Agent.instance.transaction_sampler
        sampler.add_segment_parameters( :transaction_guid => appdata[APPDATA_TXN_GUID_INDEX] )

      end


      # Return the set of metric names that correspond to
      # the given +request+ and +response+.
      def metrics_for( http, request, response )
        metrics = common_metrics( http )

        if response_is_crossapp?( response )
          begin
            metrics.concat metrics_for_crossapp_response( http, response )
          rescue => err
            # Fall back to regular metrics if there's a problem with x-process metrics
            NewRelic::Agent.logger.debug "%p while fetching x-process metrics: %s" %
              [ err.class, err.message ]
            metrics.concat metrics_for_regular_response( http, request, response )
          end
        else
          NewRelic::Agent.logger.debug "Response doesn't have CAT headers."
          metrics.concat metrics_for_regular_response( http, request, response )
        end

        return metrics
      end


      # Return an Array of metrics used for every response.
      def common_metrics( http )
        metrics = [ "External/all" ]
        metrics << "External/#{http.address}/all"

        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          metrics << "External/allWeb"
        else
          metrics << "External/allOther"
        end

        return metrics
      end


      # Returns +true+ if Cross Application Tracing is enabled, and the given +response+
      # has the appropriate headers.
      def response_is_crossapp?( response )
        return false unless cross_app_enabled?
        unless response[NR_APPDATA_HEADER]
          NewRelic::Agent.logger.debug "Response doesn't have the %p header: %p" %
            [ NR_APPDATA_HEADER, response.to_hash ]
          return false
        end

        return true
      end


      # Return the set of metric objects appropriate for the given cross app
      # +response+.
      def metrics_for_crossapp_response( http, response )
        xp_id, txn_name, q_time, r_time, req_len, _ = extract_appdata( response )

        check_crossapp_id( xp_id )
        check_transaction_name( txn_name )

        NewRelic::Agent.logger.debug "CAT xp_id: %p, txn_name: %p." % [ xp_id, txn_name ]

        metrics = []
        metrics << "ExternalApp/#{http.address}/#{xp_id}/all"
        metrics << "ExternalTransaction/#{http.address}/#{xp_id}/#{txn_name}"

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
      def extract_appdata( response )
        appdata = response[NR_APPDATA_HEADER] or
          raise NewRelic::Agent::CrossAppTracing::Error,
            "Can't derive metrics for response: no #{NR_APPDATA_HEADER} header!"

        key = cross_app_encoding_key()
        decoded_appdata = decode_with_key( key, appdata )
        decoded_appdata.set_encoding( ::Encoding::UTF_8 ) if
          decoded_appdata.respond_to?( :set_encoding )

        return NewRelic.json_load( decoded_appdata )
      end


      # Return the set of metric objects appropriate for the given (non-cross app)
      # +response+.
      def metrics_for_regular_response( http, request, response )
        metrics = []
        metrics << "External/#{http.address}/Net::HTTP/#{request.method}"

        return metrics
      end


      # Fetch a reference to the stats engine.
      def stats_engine
        NewRelic::Agent.instance.stats_engine
      end


      # Check the given +id+ to ensure it conforms to the format of a cross-application
      # ID. Raises an NewRelic::Agent::CrossAppTracing::Error if it doesn't.
      def check_crossapp_id( id )
        id =~ /\A\d+#\d+\z/ or
          raise NewRelic::Agent::CrossAppTracing::Error,
            "malformed cross application ID %p" % [ id ]
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

