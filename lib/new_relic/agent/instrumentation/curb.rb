# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :curb

  depends_on do
    defined?(Curb)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Curb instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/curb_wrappers'
  end

  executes do
    class Curl::Multi

      def perform_with_newrelic
        NewRelic::Agent.logger.debug "Curb: perform with newrelic"
        trace_pending_requests if NewRelic::Agent.is_execution_traced?
        return perform_without_newrelic
      end


      alias perform perform_without_newrelic
      alias perform_with_newrelic perform


      def trace_pending_requests
        NewRelic::Agent.logger.debug "Curb: tracing pending requests"
        self.requests.each do |request|
          NewRelic::Agent.logger.debug "  request: %p" % [ request ]
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
            NewRelic::Agent.logger.debug "    completion callback: %p" % [ finished_request ]
            NewRelic::Agent::CrossAppTracing.finish_trace( t0, segment, wrapped_request, wrapped_response )
            existing_completion_proc.call( finished_request ) if existing_completion_proc
          end

        end
      rescue => err
        NewRelic::Agent.logger.error( "Untrapped exception", err )
      end

    end

  end
end


__END__

# Possible paths to Curl::Easy#perform that include the HTTP verb:

- Curl.http (first argument)
- Curl::Easy.perform (implicit GET)
- Curl::Easy#http_head

# Paths which require looking up the verb (Curl::Easy#getoption :customrequest)

- Curl::Easy.perform


