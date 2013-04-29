# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :sinatra

  depends_on do
    defined?(::Sinatra) && defined?(::Sinatra::Base) &&
      Sinatra::Base.private_method_defined?(:dispatch!) &&
      Sinatra::Base.private_method_defined?(:process_route) &&
      Sinatra::Base.private_method_defined?(:route_eval)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sinatra instrumentation'
  end

  executes do
    ::Sinatra::Base.class_eval do
      include NewRelic::Agent::Instrumentation::Sinatra

      # TODO: tidy up method chaining?
      alias dispatch_without_newrelic dispatch!
      alias dispatch! dispatch_with_newrelic

      alias process_route_without_newrelic process_route
      alias process_route process_route_with_newrelic

      alias route_eval_without_newrelic route_eval
      alias route_eval route_eval_with_newrelic
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
      # to match them, not directly to full URL's.
      module Sinatra
        include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

        # Expected method for supporting ControllerInstrumentation
        def newrelic_request_headers
          request.env
        end

        # Capture last route we've seen. Will set for transaction on route_eval
        def process_route_with_newrelic(*args, &block)
          # TODO: Is this guaranteed to be safe?
          # TODO: How do we behave if we don't get a block? Does that even make sense?
          env["newrelic.last_route"] = args[0]

          # TODO: Safer wrapping around making sure that we call, even if we bork?
          process_route_without_newrelic(*args, &block)
        end

        def route_eval_with_newrelic(*args, &block)
          # TODO: Check if we've got a name yet? Better error handling?
          txn_name = NewRelic.transaction_name_for_route(env["newrelic.last_route"], request)

          # TODO: Should we be generating the full name (with class) like this, or modifying existing name?
          # TODO: How does this naming interact with the user applying raw set_transaction_name in route?
          ::NewRelic::Agent.set_transaction_name("#{self.class.name}/#{txn_name}")

          # TODO: Safer wrapping around making sure that we call, even if we bork?
          route_eval_without_newrelic(*args, &block)
        end

        def dispatch_with_newrelic
          # TODO: Should the name construction here be pulled to the module below now that we do it twice?
          # TODO: Does it make sense to set the initial transaction name to UNKNOWN_METRIC, or would something more specialized be better?
          # TODO: Does this work out of the box now with abort_transaction? If not, why not? Worth testing.
          perform_action_with_newrelic_trace(:category => :sinatra,
                                             :name => NewRelic::transaction_name(::NewRelic::Agent::UNKNOWN_METRIC, request),
                                             :params => @request.params) do
            begin
              dispatch_without_newrelic
            ensure
              # Will only see an error raised if :show_exceptions is true, but
              # will always see them in the env hash if they occur
              had_error = env.has_key?('sinatra.error')
              ::NewRelic::Agent.notice_error(env['sinatra.error']) if had_error
            end
          end
        end

        # TODO: Rename/move/extract this thing. Stupid name messes with our own
        # scope lookups so we can't just say NewRelic::Agent....
        module NewRelic
          extend self

          def http_verb(request)
            request.request_method if request.respond_to?(:request_method)
          end

          def transaction_name_for_route(route, request)
            # TODO: Can this route be something other than a Regexp that will respond to source?
            transaction_name(route.source, request)
          end

          def transaction_name(route_text, request)
            name = ::NewRelic::Agent::UNKNOWN_METRIC
            verb = http_verb(request)

            # TODO: Update to better striping based on pull request we received
            name = route_text.gsub(%r{^[/^]*(.*?)[/\$\?]*$}, '\1')
            name = "#{verb} #{name}" unless verb.nil?
            name
          rescue => e
            ::NewRelic::Agent.logger.debug("#{e.class} : #{e.message} - Error encountered trying to identify Sinatra transaction name")
            ::NewRelic::Agent::UNKNOWN_METRIC
          end
        end
      end
    end
  end
end
