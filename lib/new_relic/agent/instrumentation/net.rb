if defined? Net::HTTP
  Net::HTTP.class_eval do
    def request_with_newrelic_trace(*args, &block)
      if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
        self.class.trace_execution_scoped(["External/#{@address}/Net::HTTP/#{args[0].method}",
                                           "External/#{@address}/all",
                                           "External/allWeb"]) do
          request_without_newrelic_trace(*args, &block)
        end
      else
        self.class.trace_execution_scoped(["External/#{@address}/Net::HTTP/#{args[0].method}", 
                                             "External/#{@address}/all",
                                             "External/allOther"]) do
          request_without_newrelic_trace(*args, &block)
        end
      end
    end
    alias request_without_newrelic_trace request
    alias request request_with_newrelic_trace
  end
end
