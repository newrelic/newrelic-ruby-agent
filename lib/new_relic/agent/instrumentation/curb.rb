# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :curb

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

      attr_accessor :_nr_http_verb

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

      def self::make_hooked_verb_method( verb, aliased_method_name )
        return lambda do |*args, &block|
          NewRelic::Agent.logger.debug "Setting HTTP verb to %p" % [ verb ]
          self._nr_http_verb = verb
          send( aliased_method_name )
        end
      end

      hook_verb_method :http_post, :POST
      hook_verb_method :http_put,  :PUT
      hook_verb_method :http_head, :HEAD


      def http_with_newrelic( verb )
        NewRelic::Agent.logger.debug "Setting HTTP verb to %p" % [ verb ]
        self._nr_http_verb = verb.to_s.upcase
        http_without_newrelic( verb )
      end

      alias_method :http_without_newrelic, :http
      alias_method :http, :http_with_newrelic

    end


    class Curl::Multi

      def add_with_newrelic( curl )
        NewRelic::Agent.logger.debug "Curb: add with newrelic"
        hook_pending_request( curl ) if NewRelic::Agent.is_execution_traced?
        return add_without_newrelic( curl )
      end


      alias_method :add_without_newrelic, :add
      alias_method :add, :add_with_newrelic


      def hook_pending_request( request )
        NewRelic::Agent.logger.debug "Curb: adding cross-app tracing to pending request %p:%#016x" %
           [ request, request.object_id * 2 ]

        wrapped_request =  NewRelic::Agent::HTTPClients::CurbRequest.new( request )
        wrapped_response = NewRelic::Agent::HTTPClients::CurbResponse.new( request )

        NewRelic::Agent.logger.debug "  starting trace"
        t0, segment = NewRelic::Agent::CrossAppTracing.start_trace( wrapped_request )

        existing_completion_proc = request.on_complete
        existing_header_proc = request.on_header
        NewRelic::Agent.logger.debug "  existing callbacks: completion: %p, header: %p" %
          [ existing_completion_proc, existing_header_proc ]

        request.on_header do |header_data|
          NewRelic::Agent.logger.debug "    header callback: %p" % [ header_data ]
          wrapped_response.append_header_data( header_data )
          if existing_header_proc
            existing_header_proc.call( header_data )
          else
            header_data.length
          end
        end

        request.on_complete do |finished_request|
          NewRelic::Agent.logger.debug "    completion callback: %p" % [ finished_request.headers ]
          NewRelic::Agent::CrossAppTracing.finish_trace( t0, segment, wrapped_request, wrapped_response )
          existing_completion_proc.call( finished_request ) if existing_completion_proc
        end

      # rescue => err
      #   NewRelic::Agent.logger.error( "Untrapped exception", err )
      end

    end

  end
end


