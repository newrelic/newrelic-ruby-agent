DependencyDetection.defer do
  @name = :net

  depends_on do
    defined?(Net) && defined?(Net::HTTP)
  end
  
  executes do
    ::NewRelic::Agent.logger.info 'Installing Net instrumentation'
  end
  
  executes do
    Net::HTTP.class_eval do

      def request_with_newrelic_trace(request, *args, &block)
        metrics = [
          "External/#{@address}/Net::HTTP/#{request.method}",
          "External/#{@address}/all",
          "External/all"
        ]

        if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
          metrics << "External/allWeb"
        else
          metrics << "External/allOther"
        end

        events = NewRelic::Agent.instance.events
        events.notify(:before_http_request, request)
        response = self.class.trace_execution_scoped metrics do
          request_without_newrelic_trace(request, *args, &block)
        end
        events.notify(:after_http_response, response)

        return response
      end

      alias request_without_newrelic_trace request
      alias request request_with_newrelic_trace

    end
  end
end
