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

      alias dispatch_without_newrelic dispatch!
      alias dispatch! dispatch_with_newrelic

      alias process_route_without_newrelic process_route
      alias process_route process_route_with_newrelic

      alias route_eval_without_newrelic route_eval
      alias route_eval route_eval_with_newrelic

      register NewRelic::Agent::Instrumentation::Sinatra::Ignorer
    end

    module ::Sinatra
      register NewRelic::Agent::Instrumentation::Sinatra::Ignorer
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
          begin
            env["newrelic.last_route"] = args[0]
          rescue => e
            ::NewRelic::Agent.logger.debug("Failed determining last route in Sinatra", e)
          end

          process_route_without_newrelic(*args, &block)
        end

        # If a transaction name is already set, this call will tromple over it.
        # This is intentional, as typically passing to a separate route is like
        # an entirely separate transaction, so we pick up the new name.
        #
        # If we're ignored, this remains safe, since set_transaction_name
        # care for the gating on the transaction's existence for us.
        def route_eval_with_newrelic(*args, &block)
          begin
            txn_name = TransactionNamer.transaction_name_for_route(env["newrelic.last_route"], request)
            ::NewRelic::Agent.set_transaction_name("#{self.class.name}/#{txn_name}")
          rescue => e
            ::NewRelic::Agent.logger.debug("Failed during route_eval to set transaction name", e)
          end

          route_eval_without_newrelic(*args, &block)
        end

        def dispatch_with_newrelic
          return dispatch_and_notice_errors_with_newrelic if ignore_request?

          name = TransactionNamer.initial_transaction_name(request)
          perform_action_with_newrelic_trace(:category => :sinatra,
                                             :name => name,
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

        module TransactionNamer
          extend self

          def transaction_name_for_route(route, request)
            transaction_name(route.source, request)
          end

          def initial_transaction_name(request)
            transaction_name(::NewRelic::Agent::UNKNOWN_METRIC, request)
          end

          def transaction_name(route_text, request)
            verb = http_verb(request)

            name = route_text.gsub(%r{^[/^\\A]*(.*?)[/\$\?\\z]*$}, '\1')
            name = "#{verb} #{name}" unless verb.nil?
            name
          rescue => e
            ::NewRelic::Agent.logger.debug("#{e.class} : #{e.message} - Error encountered trying to identify Sinatra transaction name")
            ::NewRelic::Agent::UNKNOWN_METRIC
          end

          def http_verb(request)
            request.request_method if request.respond_to?(:request_method)
          end
        end

        def ignore_request?
          settings.newrelic_ignore_routes.any? do |pattern|
            pattern.match(request.path_info)
          end
        end

        module Ignorer
          def self.registered(app)
            app.set :newrelic_ignore_routes, [] unless app.respond_to?(:newrelic_ignore_routes)
          end

          def newrelic_ignore(*routes)
            settings.newrelic_ignore_routes += routes.map do |r|
              # Ugly sending to private Base#compile, but we want to mimic
              # exactly Sinatra's mapping of route text to regex
              send(:compile, r).first
            end
          end
        end
      end
    end
  end
end
