module NewRelic::Agent::Instrumentation
  module ErrorInstrumentation
    module Shim
      def newrelic_notice_error(*args); end      
    end
    # Send the error instance to New Relic.
    # +metric_path+ is the optional metric identifier given for the context of the error.
    # +param_info+ is additional hash of info to be shown with the error. 
    def newrelic_notice_error(exception, metric_path = nil, param_info = {})
      metric_path ||= self.newrelic_metric_path if self.respond_to? :newrelic_metric_path 
      NewRelic::Agent.agent.error_collector.notice_error(exception, nil, metric_path, param_info)
    end
  end
end