# ActiveMerchant Instrumentation.

if defined? Net::HTTP
#  operations = %w[request]
#  for op in operations do
    Net::HTTP.class_eval do
      add_method_tracer "request", 'External/#{@address}/Net::HTTP/#{args[0].method}'# + op 
      add_method_tracer "request", 'External/#{@address}/all', :push_scope => false
      add_method_tracer "request", 'External/all', :push_scope => false
    end
#  end
end
