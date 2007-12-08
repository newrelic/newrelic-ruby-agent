require 'seldon/agent/agent'
require 'seldon/agent/method_tracer'
require 'seldon/agent/session_tracer' if false # turn off for now until we get it working

require 'dispatcher'
require 'erb'

# Instrumentation for the key code points inside rails for monitoring by Seldon.
# note this file is loaded only if the seldon agent is enabled (through config/seldon.yml)
module ActionController
  class Base
    
    def perform_action_with_trace
      # don't trace if this is a web service...
      return perform_action_without_trace if is_web_service_controller?

      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution "Controller", false do 
        # generate metrics for this specific action
        self.class.trace_method_execution "Controller/#{controller_path}/#{action_name}" do 
          perform_action_without_trace
        end
      end
    end
    
    alias_method_chain :perform_action, :trace
    
    add_method_tracer :render, 'View/#{controller_name}/#{action_name}/Rendering'
    add_method_tracer :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
   
    # trace the number of exceptions encountered 
    # TODO determine how to break these out: by error code, contoller class, error class? all of the above?
    add_method_tracer :rescue_action, 'Errors/Type/#{args.first.class}'
    add_method_tracer :rescue_action, 'Errors/Controller/#{self.class}'
    
    private
      def is_web_service_controller?
        # TODO this only covers the case for Direct implementation.
        self.class.read_inheritable_attribute("web_service_api")
      end
  end
end

# instrumentation for Web Service martialing - XML RPC
class ActionWebService::Protocol::XmlRpc::XmlRpcProtocol
  add_method_tracer :decode_request, "WebService/Xml Rpc/XML Decode"
  add_method_tracer :encode_request, "WebService/Xml Rpc/XML Encode"
  add_method_tracer :decode_response, "WebService/Xml Rpc/XML Decode"
  add_method_tracer :encode_response, "WebService/Xml Rpc/XML Encode"
end

# instrumentation for Web Service martialing - Soap
class ActionWebService::Protocol::Soap::SoapProtocol
  add_method_tracer :decode_request, "WebService/Soap/XML Decode"
  add_method_tracer :encode_request, "WebService/Soap/XML Encode"
  add_method_tracer :decode_response, "WebService/Soap/XML Decode"
  add_method_tracer :encode_response, "WebService/Soap/XML Encode"
end

# instrumentation for dynamic application code loading
module Dependencies
  add_method_tracer :load_file, "Rails/Application Code Loading"
end

# instrumentation for ActiveRecord
# FIXME revisit metric names.  Consider: read/write/delete or select/update/insert/delete
module ActiveRecord
  class Base
    class << self
      add_method_tracer :find, 'ActiveRecord/#{self.name}/find'
      add_method_tracer :find, 'ActiveRecord/find', false
      add_method_tracer :find, 'ActiveRecord/all', false
    end
    
    add_method_tracer :create_or_update, 'ActiveRecord/#{self.class.name}/save'
    add_method_tracer :create_or_update, 'ActiveRecord/save', false
    add_method_tracer :create_or_update, 'ActiveRecord/all', false

    add_method_tracer :destroy, 'ActiveRecord/#{self.class.name}/destroy'
    add_method_tracer :destroy, 'ActiveRecord/destroy', false
    add_method_tracer :destroy, 'ActiveRecord/all', false
  end
end

# instrumentation for core rails dispatching
class Dispatcher
  class << self
    add_method_tracer :dispatch, 'Rails/HTTP Dispatch', false
    add_method_tracer 'reset_application!', 'Rails/Application Reset', false
  end
end

class ERB::Compiler
  add_method_tracer :compile, 'View/.rhtml Processing'
end


