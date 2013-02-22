# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


DependencyDetection.defer do
  @name = :net

  depends_on do
    defined?(Net) && defined?(Net::HTTP)
  end
  
  executes do
    ::NewRelic::Agent.logger.info 'Installing Net instrumentation'
  end

  executes do
    class Net::HTTP
      include NewRelic::Agent::CrossAppMonitor::EncodingFunctions


      # Exception raised if there is a problem with cross app transactions.
      class CrossAppError < RuntimeError; end


      # The cross app response header for "outgoing" calls
      NR_APPDATA_HEADER = 'X-NewRelic-App-Data'

      # The cross app request header for "outgoing" calls
      NR_ID_HEADER = 'X-NewRelic-ID'


      # Instrument outgoing HTTP requests and fire associated events back
      # into the Agent.
      def request_with_newrelic_trace(request, *args, &block)
        events = NewRelic::Agent.instance.events

        inject_request_header( request ) if cross_app_enabled?
        response = trace_http_request( request, *args, &block )

        return response
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace


      # Return +true+ if cross app tracing is enabled in the config.
      def cross_app_enabled?
        NewRelic::Agent.config[:cross_application_tracing]
      end


      # Memoized fetcher for the cross app encoding key. Raises a 
      # Net::HTTP::CrossAppError if the key isn't configured.
      def cross_app_encoding_key
        @key ||= NewRelic::Agent.config[:encoding_key] or
          raise Net::HTTP::CrossAppError, "No encoding_key set."
      end


      # Inject the X-Process header into the outgoing +request+.
      def inject_request_header( request )
        cross_app_id = NewRelic::Agent.config[:cross_app_id] or
          raise Net::HTTP::CrossAppError, "no cross app ID configured"
        key = cross_app_encoding_key()

        request[ NR_ID_HEADER ] = obfuscate_with_key( key, cross_app_id )

      rescue Net::HTTP::CrossAppError => err
        NewRelic::Agent.logger.debug "Not injecting x-process header: %s" % [ err.message ]
      end


      # Send the given +request+, adding metrics appropriate to the
      # response when it comes back.
      def trace_http_request( request, *args, &block )
        return request_without_newrelic_trace(request, *args, &block) unless
          NewRelic::Agent.is_execution_traced?

        t0 = Time.now
        response = request_without_newrelic_trace( request, *args, &block )

        # If the block is exiting normally
        duration = (Time.now - t0).to_f
        stats = metrics_for( request, response )
        stats.each { |stat| stat.trace_call(duration) }

        return response
      rescue Net::HTTP::CrossAppError => err
        NewRelic::Agent.logger.debug "%p in cross app tracing: %s" % [ err.class, err.message ]
      end


      # Return the set of metrics (NewRelic::MethodTraceStats objects) that correspond to
      # the given +request+ and +response+.
      def metrics_for( request, response )
        metrics = common_metrics()

        if response_is_crossapp?( response )
          begin
            metrics += metrics_for_crossapp_response( response )
          rescue => err
            # Fall back to regular metrics if there's a problem with x-process metrics
            NewRelic::Agent.logger.debug "%p while fetching x-process metrics: %s" %
              [ err.class, err.message ]
            metrics += metrics_for_regular_response( request, response )
          end
        else
          metrics += metrics_for_regular_response( request, response )
        end

        return metrics
      end


      # Return an Array of metrics used for every response.
      def common_metrics
        NewRelic::Agent.logger.debug "Fetching common metrics"
        metrics = [ get_metric("External/all") ]
        metrics << get_metric( "External/#@address/all" )

        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          metrics << get_metric( "External/allWeb" )
        else
          metrics << get_metric( "External/allOther" )
        end

        return metrics
      end


      # Returns +true+ if Cross Application Tracing is enabled, and the given +response+
      # has the appropriate headers.
      def response_is_crossapp?( response )
        return cross_app_enabled? && response[NR_APPDATA_HEADER]
      end


      # Return the set of metric objects appropriate for the given cross app
      # +response+.
      def metrics_for_crossapp_response( response )
        xp_id, txn_name, q_time, r_time, req_len, _ = extract_appdata( response )

        check_crossapp_id( xp_id )
        check_transaction_name( txn_name )

        metrics = []
        metrics << get_metric( "ExternalApp/#@address/#{xp_id}/all" )
        metrics << get_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )
        metrics << get_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )
        metrics << get_scoped_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )

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
      #    <request content length in bytes>
      #  ]
      def extract_appdata( response )
        appdata = response[NR_APPDATA_HEADER] or
          raise Net::HTTP::CrossAppError,
            "Can't derive metrics for response: no #{NR_APPDATA_HEADER} header!"

        key = cross_app_encoding_key()
        decoded_appdata = decode_with_key( key, appdata )
        decoded_appdata.set_encoding( ::Encoding::UTF_8 ) if
          decoded_appdata.respond_to?( :set_encoding )

        return NewRelic.json_load( decoded_appdata )
      end


      # Return the set of metric objects appropriate for the given (non-cross app)
      # +response+.
      def metrics_for_regular_response( request, response )
        metrics = []
        metrics << get_metric( "External/#@address/Net::HTTP/#{request.method}" )
        
        return metrics
      end


      # Convenience function for fetching the metric associated with +metric_name+.
      def get_metric( metric_name )
        NewRelic::Agent.instance.stats_engine.get_stats_no_scope( metric_name )
      end


      # Convenience function for fetching the scoped metric associated with +metric_name+.
      def get_scoped_metric( metric_name )
        # Default is to use the metric_name itself as the scope, which is what we want
        NewRelic::Agent.instance.stats_engine.get_stats( metric_name )
      end


      # Check the given +id+ to ensure it conforms to the format of a cross-application
      # ID. Raises an Net::HTTP::CrossAppError if it doesn't.
      def check_crossapp_id( id )
        id =~ /\A\d+#\d+\z/ or
          raise Net::HTTP::CrossAppError, "malformed cross application ID %p" % [ id ]
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
