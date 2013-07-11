# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :curb

  depends_on do
    defined?(Curl)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Curb instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/curb_wrappers'
  end

  executes do
    class Curl::Easy

      attr_accessor :_nr_http_verb,
                    :_nr_serial

      # Set up an alias for the method +methname+ that will store the associated
      # HTTP +verb+ for later instrumentation. This is necessary because there's no
      # way from the Curb API to determine what verb the request used from the
      # handle.
      def self::hook_verb_method( methname, verb )
        nr_method_name = "#{methname}_with_newrelic"
        aliased_method_name = "#{methname}_without_newrelic"
        method_body = self.make_hooked_verb_method( verb.to_s.upcase, aliased_method_name )

        define_method( nr_method_name, &method_body )

        alias_method aliased_method_name, methname
        alias_method methname, nr_method_name
      end


      # Make a lambda for the body of the method with the given +aliased_method_name+
      # that will set the verb on the object to +verb+. This is so the NewRelic
      # request and response adapters know what verb the request used, as there's no
      # way to recover it from a Curl::Easy after it's created.
      def self::make_hooked_verb_method( verb, aliased_method_name )
        return lambda do |*args, &block|
          NewRelic::Agent.logger.debug "Setting HTTP verb to %p" % [ verb ]
          self._nr_http_verb = verb
          __send__( aliased_method_name )
        end
      end

      hook_verb_method :http_post, :POST
      hook_verb_method :http_put,  :PUT
      hook_verb_method :http_head, :HEAD


      # Hook the #http method to set the verb.
      def http_with_newrelic( verb )
        NewRelic::Agent.logger.debug "Setting HTTP verb to %p" % [ verb ]
        self._nr_http_verb = verb.to_s.upcase
        http_without_newrelic( verb )
      end

      alias_method :http_without_newrelic, :http
      alias_method :http, :http_with_newrelic


      # Hook the #perform method to mark the request as non-parallel.
      def perform_with_newrelic
        NewRelic::Agent.logger.debug "Setting serial request marker"
        self._nr_serial = true
        perform_without_newrelic
      end

      alias_method :perform_without_newrelic, :perform
      alias_method :perform, :perform_with_newrelic

    end # class Curl::Easy


    class Curl::Multi
      include NewRelic::Agent::MethodTracer

      # Add CAT with callbacks if the request is serial
      def add_with_newrelic( curl )
        if curl.respond_to?( :_nr_serial ) && curl._nr_serial
          NewRelic::Agent.logger.debug "Curb: add with newrelic"
          hook_pending_request( curl ) if NewRelic::Agent.is_execution_traced?
        end

        return add_without_newrelic( curl )
      end

      alias_method :add_without_newrelic, :add
      alias_method :add, :add_with_newrelic


      # Trace as an External/Multiple call if the first request isn't serial.
      def perform_with_newrelic
        return perform_without_newrelic if
          self.requests.first &&
          self.requests.first.respond_to?( :_nr_serial ) &&
          self.requests.first._nr_serial

        trace_execution_scoped("External/Multiple/Curb::Multi/perform") do
          perform_without_newrelic
        end
      end

      alias_method :perform_without_newrelic, :perform
      alias_method :perform, :perform_with_newrelic


      # Instrument the specified +request+ (a Curl::Easy object) and set up cross-application
      # tracing if it's enabled.
      def hook_pending_request( request )
        NewRelic::Agent.logger.debug "Curb: adding cross-app tracing to pending request %p:%#016x" %
           [ request, request.object_id * 2 ]

        wrapped_request, wrapped_response = wrap_request( request )

        NewRelic::Agent.logger.debug "  starting trace"
        t0, segment = NewRelic::Agent::CrossAppTracing.start_trace( wrapped_request )

        install_header_callback( request, wrapped_response )
        install_completion_callback( request, t0, segment, wrapped_request, wrapped_response )
      rescue => err
        NewRelic::Agent.logger.error( "Untrapped exception", err )
      end


      # Create request and response adapter objects for the specified +request+
      def wrap_request( request )
        return NewRelic::Agent::HTTPClients::CurbRequest.new( request ),
               NewRelic::Agent::HTTPClients::CurbResponse.new( request )
      end


      # Install a callback that will record the response headers to enable
      # CAT linking
      def install_header_callback( request, wrapped_response )
        existing_header_proc = request.on_header
        request.on_header do |header_data|
          NewRelic::Agent.logger.debug "    header callback: %p" % [ header_data ]
          wrapped_response.append_header_data( header_data )

          if existing_header_proc
            existing_header_proc.call( header_data )
          else
            header_data.length
          end
        end
      end


      # Install a callback that will finish the trace.
      def install_completion_callback( request, t0, segment, wrapped_request, wrapped_response )
        existing_completion_proc = request.on_complete
        request.on_complete do |finished_request|
          NewRelic::Agent.logger.debug "    completion callback: %p" % [ finished_request.headers ]
          NewRelic::Agent::CrossAppTracing.finish_trace( t0, segment, wrapped_request, wrapped_response )
          existing_completion_proc.call( finished_request ) if existing_completion_proc
        end
      end

    end # class Curl::Multi

  end
end


