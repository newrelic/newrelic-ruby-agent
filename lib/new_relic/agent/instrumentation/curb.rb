# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :curb

  CURB_MIN_VERSION = ::NewRelic::VersionNumber.new("0.8.1")

  depends_on do
    defined?(::Curl) && defined?(::Curl::CURB_VERSION) &&
      ::NewRelic::VersionNumber.new(::Curl::CURB_VERSION) >= CURB_MIN_VERSION
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Curb instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/curb_wrappers'
  end

  executes do
    class Curl::Easy

      attr_accessor :_nr_instrumented,
                    :_nr_http_verb,
                    :_nr_header_str,
                    :_nr_original_on_header,
                    :_nr_original_on_complete,
                    :_nr_serial

      module NewRelicInstrumentation

        # We have to hook these three methods separately, as they don't use
        # Curl::Easy#http
        def http_head(*args, &blk)
          self._nr_http_verb = :HEAD
          http_head(*args, &blk)
        end

        def http_post(*args, &blk)
          self._nr_http_verb = :POST
          http_post(*args, &blk)
        end

        def http_put(*args, &blk)
          self._nr_http_verb = :PUT
          http_put(*args, &blk)
        end


        # Hook the #http method to set the verb.
        def http( verb )
          self._nr_http_verb = verb.to_s.upcase
          http( verb )
        end


        # Hook the #perform method to mark the request as non-parallel.
        def perform
          self._nr_serial = true
          perform
        end

        # We override this method in order to ensure access to header_str even
        # though we use an on_header callback
        def header_str
          if self._nr_serial
            self._nr_header_str
          else
            # Since we didn't install a header callback for a non-serial request,
            # just fall back to the original implementation.
            header_str
          end
        end
      end
      prepend NewRelicInstrumentation
    end # class Curl::Easy


    class Curl::Multi
      include NewRelic::Agent::MethodTracer

      module NewRelicInstrumentation
        # Add CAT with callbacks if the request is serial
        def add(curl) #THREAD_LOCAL_ACCESS
          if curl.respond_to?(:_nr_serial) && curl._nr_serial
            hook_pending_request(curl) if NewRelic::Agent.tl_is_execution_traced?
          end

          return super( curl )
        end


        # Trace as an External/Multiple call if the first request isn't serial.
        def perform(&blk)
          return super if
            self.requests.first &&
            self.requests.first.respond_to?(:_nr_serial) &&
            self.requests.first._nr_serial

          trace_execution_scoped("External/Multiple/Curb::Multi/perform") do
            super(&blk)
          end
        end
      end
      prepend NewRelicInstrumentation

      # Instrument the specified +request+ (a Curl::Easy object) and set up cross-application
      # tracing if it's enabled.
      def hook_pending_request(request) #THREAD_LOCAL_ACCESS
        wrapped_request, wrapped_response = wrap_request(request)
        state = NewRelic::Agent::TransactionState.tl_get
        t0    = Time.now
        node  = NewRelic::Agent::CrossAppTracing.start_trace(state, t0, wrapped_request)

        unless request._nr_instrumented
          install_header_callback(request, wrapped_response)
          install_completion_callback(request, t0, node, wrapped_request, wrapped_response)
          request._nr_instrumented = true
        end
      rescue => err
        NewRelic::Agent.logger.error("Untrapped exception", err)
      end


      # Create request and response adapter objects for the specified +request+
      def wrap_request(request)
        return NewRelic::Agent::HTTPClients::CurbRequest.new(request),
               NewRelic::Agent::HTTPClients::CurbResponse.new(request)
      end


      # Install a callback that will record the response headers to enable
      # CAT linking
      def install_header_callback( request, wrapped_response )
        original_callback = request.on_header
        request._nr_original_on_header = original_callback
        request._nr_header_str = ''
        request.on_header do |header_data|
          wrapped_response.append_header_data( header_data )

          if original_callback
            original_callback.call( header_data )
          else
            header_data.length
          end
        end
      end

      # Install a callback that will finish the trace.
      def install_completion_callback(request, t0, node, wrapped_request, wrapped_response) #THREAD_LOCAL_ACCESS
        original_callback = request.on_complete
        request._nr_original_on_complete = original_callback
        request.on_complete do |finished_request|
          begin
            state = NewRelic::Agent::TransactionState.tl_get
            NewRelic::Agent::CrossAppTracing.finish_trace(state, t0, node, wrapped_request, wrapped_response)
          ensure
            # Make sure the existing completion callback is run, and restore the
            # on_complete callback to how it was before.
            original_callback.call(finished_request) if original_callback
            remove_instrumentation_callbacks(request)
          end
        end
      end

      def remove_instrumentation_callbacks(request)
        request.on_complete(&request._nr_original_on_complete)
        request.on_header(&request._nr_original_on_header)
        request._nr_instrumented = false
      end

    end # class Curl::Multi

  end
end
