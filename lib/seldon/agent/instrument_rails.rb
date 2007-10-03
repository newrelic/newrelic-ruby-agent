require 'seldon/agent/agent'
require 'seldon/agent/method_tracer'

# instrumentation for all controllers except webservice implementations
module ActionController
  class Base
    
    def perform_action_with_trace
      # don't trace if this is a web service...
      return perform_action_without_trace if is_web_service_controller?
      
      metric_name = "Controller/#{controller_name}/#{action_name}"
      self.class.trace_method_execution metric_name do 
        perform_action_without_trace
      end
    end
    alias_method_chain :perform_action, :trace
    
    add_tracer_to_method :process, '#{metric_name_for_request(args.first)}'
    add_tracer_to_method :render, 'View/#{controller_name}/#{action_name}/Rendering'
    add_tracer_to_method :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
    
    private
      def is_web_service_controller?
        # TODO this only covers the case for Direct implementation.
        self.class.read_inheritable_attribute("web_service_api")
      end
      
      # this utility determines the URL metric that should be used for a specific path.
      # FIXME need to normalize this - right now, manually entered urls generate unique metrics
      def metric_name_for_request(request)
        "URL#{request.path}"
      end
  end
end

# instrumentation for Web Service martialing - XML RPC
class ActionWebService::Protocol::XmlRpc::XmlRpcProtocol
  add_tracer_to_method :decode_request, "WebService/Xml Rpc/XML Decode"
  add_tracer_to_method :encode_request, "WebService/Xml Rpc/XML Encode"
  add_tracer_to_method :decode_response, "WebService/Xml Rpc/XML Decode"
  add_tracer_to_method :encode_response, "WebService/Xml Rpc/XML Encode"
end

# instrumentation for Web Service martialing - Soap
class ActionWebService::Protocol::Soap::SoapProtocol
  add_tracer_to_method :decode_request, "WebService/Soap/XML Decode"
  add_tracer_to_method :encode_request, "WebService/Soap/XML Encode"
  add_tracer_to_method :decode_response, "WebService/Soap/XML Decode"
  add_tracer_to_method :encode_response, "WebService/Soap/XML Encode"
end

# instrumentation for dynamic application code loading
module Dependencies
  add_tracer_to_method :load_file, "Rails/Application Code Loading"
end

# instrumentation for ActiveRecord
module ActiveRecord
  class Base
    class << self
      add_tracer_to_method :find, 'ActiveRecord/#{self.name}/find'
    end
    add_tracer_to_method :save, 'ActiveRecord/#{self.class.name}/save'
  end
end

=begin
Here is the stack trace for the web server CGI dispatcher


/usr/local/lib/ruby/gems/1.8/gems/actionpack-1.13.3/lib/action_controller/base.rb:430:in `send'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-1.13.3/lib/action_controller/base.rb:430:in `process_without_filters'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-1.13.3/lib/action_controller/filters.rb:624:in `process_without_session_management_support'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-1.13.3/lib/action_controller/session_management.rb:114:in `process_without_trace'
/usr/local/lib/ruby/gems/1.8/gems/actionpack-1.13.3/lib/action_controller/base.rb:330:in `process'
/usr/local/lib/ruby/gems/1.8/gems/rails-1.2.3/lib/dispatcher.rb:41:in `dispatch'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/rails.rb:78:in `process'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/rails.rb:76:in `synchronize'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/rails.rb:76:in `process'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:618:in `process_client'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:617:in `each'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:617:in `process_client'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:736:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:736:in `initialize'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:736:in `new'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:736:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:720:in `initialize'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:720:in `new'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel.rb:720:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/configurator.rb:271:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/configurator.rb:270:in `each'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/configurator.rb:270:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/bin/mongrel_rails:127:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/lib/mongrel/command.rb:211:in `run'
/usr/local/lib/ruby/gems/1.8/gems/mongrel-1.0.1/bin/mongrel_rails:243

=end



