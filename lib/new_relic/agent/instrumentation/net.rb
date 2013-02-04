# encoding: utf-8

DependencyDetection.defer do
  @name = :net

  depends_on do
    defined?(Net) && defined?(Net::HTTP)
  end
  
  executes do
    ::NewRelic::Agent.logger.info 'Installing Net instrumentation'
  end

  executes do
    require 'base64'
  end
  
  executes do
    class Net::HTTP

      # The cross-process header for "outgoing" calls
      NR_APPDATA_HEADER = 'X-NewRelic-App-Data'


      # Instrument outgoing HTTP requests and fire associated events back
      # into the Agent.
      def request_with_newrelic_trace(request, *args, &block)
        events = NewRelic::Agent.instance.events

        events.notify( :before_http_request, request )
        response = trace_http_request( request, *args, &block )
        events.notify( :after_http_response, response )

        return response
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace


      # Send the given +request+, adding metrics appropriate to the
      # response when it comes back.
      def trace_http_request( request, *args, &block )
        return request_without_newrelic_trace(request, *args, &block) unless
          NewRelic::Agent.is_execution_traced?

        t0 = Time.now
        response = request_without_newrelic_trace( request, *args, &block )

        return response
      ensure
        # If the block is exiting normally
        if t0 && response
          duration = (Time.now - t0).to_f

          stats = metrics_for( request, response )
          stats.each { |stat| stat.trace_call(duration) }
        end
      end


      # Return the set of metrics (NewRelic::MethodTraceStats objects) that correspond to
      # the given +request+ and +response+.
      def metrics_for( request, response )
        metrics = common_metrics()

        if response_is_xprocess?( response )
          metrics += metrics_for_xprocess_response( response )
        else
          metrics += metrics_for_regular_response( request, response )
        end

        return metrics
      end


      # Return an Array of metrics used for every response.
      def common_metrics
        metrics = [ get_metric("External/all") ]

        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          metrics << get_metric( "External/allWeb" )
        else
          metrics << get_metric( "External/allOther" )
        end

        return metrics
      end


      # Returns +true+ if Cross-Process tracing is enabled, and the given +response+
      # has the appropriate headers.
      def response_is_xprocess?( response )
        return NewRelic::Agent.config[:'cross_process.enabled'] && response[NR_APPDATA_HEADER]
      end


      # Return the set of metric objects appropriate for the given cross-process
      # +response+.
      def metrics_for_xprocess_response( response )
        appdata = response[NR_APPDATA_HEADER] or
          raise "Can't derive metrics for response: no #{NR_APPDATA_HEADER} header!"

        decoded_appdata = Base64.decode64( appdata )
        decoded_appdata.set_encoding( ::Encoding::UTF_8 ) if
          decoded_appdata.respond_to?( :set_encoding )

        xp_id, txn_name, q_time, r_time, req_len = NewRelic.json_load( decoded_appdata )

        metrics = []
        metrics << get_metric( "ExternalApp/#@address/#{xp_id}/all" )
        metrics << get_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )
        metrics << get_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )
        metrics << get_scoped_metric( "ExternalTransaction/#@address/#{xp_id}/#{txn_name}" )

        return metrics
      end


      # Return the set of metric objects appropriate for the given (non-cross-process)
      # +response+.
      def metrics_for_regular_response( request, response )
        metrics = []
        metrics << get_metric( "External/#@address/Net::HTTP/#{request.method}" )
        metrics << get_metric( "External/#@address/all" )
        
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

    end
  end
end
