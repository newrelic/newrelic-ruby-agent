# NewRelic instrumentation for controllers
#
# This instrumentation is applied to the action controller by default if the agent
# is actively collecting statistics.  It will collect statistics for the 
# given action.
#
# In cases where you don't want to instrument the top level action, but instead
# have other methods which are dispatched to by your action, and you want to treat
# these as distinct actions, then what you need to do is use
# #perform_action_with_newrelic_trace
#

module NewRelic::Agent::Instrumentation
  module SinatraInstrumentation

    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def route_eval_with_newrelic(&block_arg)
      path = unescape(@request.path_info)
      name = path
      # Go through each route and look for a match
      if routes = self.class.routes[@request.request_method]
        routes.detect do |pattern, keys, conditions, block|
          if block_arg.equal? block
            name = pattern.source
          end
        end
      end
      # strip of leading ^ and / chars and trailing $ and /
      name.gsub!(%r{^[/^]*(.*?)[/\$]*$}, '\1')
      name = 'root' if name.empty?
      perform_action_with_newrelic_trace(:name => name) do
        route_eval_without_newrelic(&block_arg)
      end
    end
  end
  
  Sinatra::Base.class_eval do
    include NewRelic::Agent::Instrumentation::SinatraInstrumentation
    alias route_eval_without_newrelic route_eval
    alias route_eval route_eval_with_newrelic
  end
  
end if defined?(Sinatra::Base)