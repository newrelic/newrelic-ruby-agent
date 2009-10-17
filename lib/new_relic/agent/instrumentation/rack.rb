# == Instrumentation for Rack ==
#
# New Relic will instrument a #call method as if it were a controller
# action, collecting transaction traces and errors.  The middleware will
# be identified only by it's class, so if you want to instrument multiple
# actions in a middleware, you need to use
# NewRelic::Agent::Instrumentation::ControllerInstrumentation::ClassMethods#add_transaction_tracer
#
# Example:
#   require 'new_relic/agent/instrumentation/rack'
#   class Middleware
#     def call(env)
#       ...
#     end
#     # Do the include after the call method is defined:
#     include NewRelic::Agent::Instrumentation::Rack
#   end

require 'new_relic/agent/instrumentation/controller_instrumentation'

module NewRelic
  module Agent
    module Instrumentation
      module Rack
        include ControllerInstrumentation
        def call_with_newrelic(*args)
          perform_action_with_newrelic_trace(:category => :rack) do
            call_without_newrelic(*args)
          end
        end
        def self.included middleware
          middleware.class_eval do
            alias call_without_newrelic call
            alias call call_with_newrelic
          end
        end
        def self.extended middleware
          middleware.class_eval do
            class << self
              alias call_without_newrelic call
              alias call call_with_newrelic
            end
          end
        end
      end
    end
  end
end
