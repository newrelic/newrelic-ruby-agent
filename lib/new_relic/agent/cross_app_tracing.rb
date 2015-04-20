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

      # Send the given +request+, adding metrics appropriate to the
      # response when it comes back.
      #
      # See the documentation for +start_trace+ for an explanation of what
      # +request+ should look like.
      #
      def tl_trace_http_request(request)
        state = NewRelic::Agent::TransactionState.tl_get
        return yield unless state.is_execution_traced?

        # It's important to set t0 outside the ensured block, otherwise there's
        # a race condition if we raise after begin but before t0's set.
        t0 = Time.now
        begin
          node = start_trace(state, t0, request)
          response = yield
        ensure
          finish_trace(state, t0, node, request, response)
        end

        return response
      end

      # Set up the necessary state for cross-application tracing before the
      # given +request+ goes out.
      #
      # The +request+ object passed in must respond to the following methods:
      #
      # * type - Return a String describing the underlying library being used
      #          to make the request (e.g. 'Net::HTTP' or 'Typhoeus')
      # * host - Return a String with the hostname or IP of the host being
      #          communicated with.
      # * method  - Return a String with the HTTP method name for this request
      # * [](key) - Lookup an HTTP request header by name
      # * []=(key, val) - Set an HTTP request header by name
      # * uri  - Full URI of the request
      #
      # This method returns the transaction node if it was sucessfully pushed.
      def start_trace(state, t0, request)
        inject_request_headers(state, request) if cross_app_enabled?
        stack = state.traced_method_stack
        node = stack.push_frame(state, :http_request, t0)

        return node
      rescue => err
        NewRelic::Agent.logger.error "Uncaught exception while tracing HTTP request", err
        return nil
      rescue Exception => e
        NewRelic::Agent.logger.debug "Unexpected exception raised while tracing HTTP request", e

        raise e
      end


      # Finish tracing the HTTP +request+ that started at +t0+ with the information in
      # +response+ and the given +http+ connection.
      #
      # The +request+ must conform to the same interface described in the documentation
      # for +start_trace+.
      #
      # The +response+ must respond to the following methods:
      #
      # * [](key) - Reads response headers.
      # * to_hash - Converts response headers to a Hash
      #
      def finish_trace(state, t0, node, request, response)
        unless t0
          NewRelic::Agent.logger.error("HTTP request trace finished without start time. This is probably an agent bug.")
          return
        end

        t1 = Time.now
        duration = t1.to_f - t0.to_f

        begin
          if request
            # Figure out which metrics we need to report based on the request and response
            # The last (most-specific) one is scoped.
            metrics = metrics_for(request, response)
            scoped_metric = metrics.pop

            stats_engine.record_scoped_and_unscoped_metrics(
              state, scoped_metric, metrics, duration)

            # If we don't have node, something failed during start_trace so
            # the current node isn't the HTTP call it should have been.
            if node
              node.name = scoped_metric
              add_transaction_trace_parameters(request, response)
            end
          end
        ensure
          # If we have a node, always pop the traced method stack to avoid
          # an inconsistent state, which prevents tracing of whole transaction.
          if node
            stack = state.traced_method_stack
            stack.pop_frame(state, node, scoped_metric, t1)
          end
        end
      rescue NewRelic::Agent::CrossAppTracing::Error => err
        NewRelic::Agent.logger.debug "while cross app tracing", err
      rescue => err
        NewRelic::Agent.logger.error "Uncaught exception while finishing an HTTP request trace", err
      end

      # Return +true+ if cross app tracing is enabled in the config.
      def cross_app_enabled?
        valid_cross_process_id? &&
          valid_encoding_key? &&
          cross_application_tracer_enabled?
      end

      def valid_cross_process_id?
        NewRelic::Agent.config[:cross_process_id] && NewRelic::Agent.config[:cross_process_id].length > 0
      end

      def valid_encoding_key?
        NewRelic::Agent.config[:encoding_key] && NewRelic::Agent.config[:encoding_key].length > 0
      end

      def cross_application_tracer_enabled?
        NewRelic::Agent.config[:"cross_application_tracer.enabled"] || NewRelic::Agent.config[:cross_application_tracing]
      end

      # Fetcher for the cross app encoding key. Raises a
      # NewRelic::Agent::CrossAppTracing::Error if the key isn't configured.
      def cross_app_encoding_key
        NewRelic::Agent.config[:encoding_key] or
          raise NewRelic::Agent::CrossAppTracing::Error, "No encoding_key set."
      end

      def obfuscator
        @obfuscator ||= NewRelic::Agent::Obfuscator.new(cross_app_encoding_key)
      end

      # Inject the X-Process header into the outgoing +request+.
      def inject_request_headers(state, request)
        cross_app_id = NewRelic::Agent.config[:cross_process_id] or
          raise NewRelic::Agent::CrossAppTracing::Error, "no cross app ID configured"

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

      def add_transaction_trace_parameters(request, response)
        filtered_uri = ::NewRelic::Agent::HTTPClients::URIUtil.filter_uri(request.uri)
        transaction_sampler.add_node_parameters(:uri => filtered_uri)
        if response && response_is_crossapp?(response)
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

        if response && response_is_crossapp?( response )
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


      # Returns +true+ if Cross Application Tracing is enabled, and the given +response+
      # has the appropriate headers.
      def response_is_crossapp?( response )
        return false unless cross_app_enabled?
        unless response[NR_APPDATA_HEADER]
          return false
        end

        return true
      end


      # Return the set of metric objects appropriate for the given cross app
      # +response+.
      def metrics_for_crossapp_response( request, response )
        xp_id, txn_name, _q_time, _r_time, _req_len, _ = extract_appdata( response )

        check_crossapp_id( xp_id )
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
      def extract_appdata( response )
        appdata = response[NR_APPDATA_HEADER] or
          raise NewRelic::Agent::CrossAppTracing::Error,
            "Can't derive metrics for response: no #{NR_APPDATA_HEADER} header!"

        decoded_appdata = obfuscator.deobfuscate( appdata )
        decoded_appdata.set_encoding( ::Encoding::UTF_8 ) if
          decoded_appdata.respond_to?( :set_encoding )

        return NewRelic::JSONWrapper.load( decoded_appdata )
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
