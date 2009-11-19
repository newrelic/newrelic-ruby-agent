if defined? Net::HTTP
  Net::HTTP.class_eval do
    def request_with_newrelic_trace(*args, &block)
      if Thread::current[:newrelic_scope_stack].nil?
        request_without_newrelic_trace(*args, &block)
      else
        self.class.trace_method_execution_with_scope("External/#{@address}/Net::HTTP/#{args[0].method}",
                                                     true,
                                                     true) do
          self.class.trace_method_execution_no_scope("External/#{@address}/all") do
            self.class.trace_method_execution_no_scope("External/allWeb") do
              request_without_newrelic_trace(*args, &block)
            end
          end
        end
      end
    end
    alias request_without_newrelic_trace request
    alias request request_with_newrelic_trace
  end
end
