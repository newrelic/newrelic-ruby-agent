# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :sinatra

  depends_on do
    defined?(::Sinatra) && defined?(::Sinatra::Base) &&
      Sinatra::Base.private_method_defined?(:dispatch!) &&
      Sinatra::Base.private_method_defined?(:process_route)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sinatra instrumentation'
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
          # We're trying to determine the transaction name via Sinatra's
          # process_route, but calling it here misses Sinatra's normal error handling.
          #
          # Relies on transaction_name to always safely return a value for us
          txn_name = NewRelic.transaction_name(self.class.routes, @request) do |pattern, keys, conditions|
            result = process_route(pattern, keys, conditions) do
              pattern.source
            end
            result if result.class == String
          end

          perform_action_with_newrelic_trace(:category => :sinatra,
                                             :name => txn_name,
                                             :params => @request.params) do
            dispatch_and_notice_errors_with_newrelic
          end
        end

        def dispatch_and_notice_errors_with_newrelic
          dispatch_without_newrelic
        ensure
          # Will only see an error raised if :show_exceptions is true, but
          # will always see them in the env hash if they occur
          had_error = env.has_key?('sinatra.error')
          ::NewRelic::Agent.notice_error(env['sinatra.error']) if had_error
        end

        # Define Request Header accessor for Sinatra
        def newrelic_request_headers
          request.env
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
              if route = yield(pattern, keys, conditions)
                name = route
                # it's important we short circuit here.  Otherwise we risk
                # applying conditions from lower priority routes which can
                # break the action.
                break
              end
            end

            name.gsub!(%r{^[/^]*(.*?)[/\$\?]*$}, '\1')
            if verb
              name = verb + ' ' + name
            end

            name
          rescue => e
            ::NewRelic::Agent.logger.debug("#{e.class} : #{e.message} - Error encountered trying to identify Sinatra transaction name")
            '(unknown)'
          end
        end
      end
    end
  end
end
