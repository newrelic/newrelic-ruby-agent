require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :sinatra
  
  depends_on do
    defined?(::Sinatra) && defined?(::Sinatra::Base) &&
      Sinatra::Base.private_method_defined?(:dispatch!)
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Sinatra instrumentation'
  end

  executes do
    ::Sinatra::Base.class_eval do
      include NewRelic::Agent::Instrumentation::Sinatra
      alias dispatch_without_newrelic dispatch!
      alias dispatch! dispatch_with_newrelic
    end
  end
end


module NewRelic
  module Agent
    module Instrumentation
      # NewRelic instrumentation for Sinatra applications.  Sinatra actions will
      # appear in the UI similar to controller actions, and have breakdown charts
      # and transaction traces.
      #
      # The actions in the UI will correspond to the pattern expression used
      # to match them.  HTTP operations are not distinguished.  Multiple matches
      # will all be tracked as separate actions.
      module Sinatra
        include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
                
        def dispatch_with_newrelic
          txn_name = NewRelic.transaction_name(self.class.routes, @request) do |pattern, keys, conditions|
            process_route(pattern, keys, conditions) do
              pattern.source
            end
          end
          
          perform_action_with_newrelic_trace(:category => :sinatra,
                                             :name => txn_name,
                                             :params => @request.params) do
            dispatch_without_newrelic
          end
        end

        module NewRelic
          extend self
          
          def http_verb(request)
            request.request_method if request.respond_to?(:request_method)
          end
          
          def transaction_name(routes, request)
            name = '(unknown)'
            verb = http_verb(request)
            
            Array(routes[verb]).each do |pattern, keys, conditions, block|
              if pattern = yield(pattern, keys, conditions)
                name = pattern
              end
            end
            
            name.gsub!(%r{^[/^]*(.*?)[/\$\?]*$}, '\1')
            if verb
              name = verb + ' ' + name
            end
            
            name
          end
        end
      end
    end
  end
end
