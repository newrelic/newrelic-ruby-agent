# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'
require 'new_relic/agent/instrumentation/sinatra/transaction_namer'
require 'new_relic/agent/instrumentation/sinatra/ignorer'
require 'new_relic/agent/parameter_filtering'

require_relative 'sinatra/chain'
require_relative 'sinatra/prepend'
require_relative 'sinatra/instrumentation'

DependencyDetection.defer do
  @name = :sinatra

  depends_on do
    !NewRelic::Agent.config[:disable_sinatra] &&
      defined?(::Sinatra) && defined?(::Sinatra::Base) &&
      Sinatra::Base.private_method_defined?(:dispatch!) &&
      Sinatra::Base.private_method_defined?(:process_route) &&
      Sinatra::Base.private_method_defined?(:route_eval)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Sinatra instrumentation'
  end

  executes do
    if use_prepend?
      ::Sinatra::Base.class_eval do
        class << self
          include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
          include NewRelic::Agent::Instrumentation::Sinatra
        end
        include NewRelic::Agent::Instrumentation::Sinatra

        register NewRelic::Agent::Instrumentation::Sinatra::Ignorer
        # chain_instrument NewRelic::Agent::Instrumentation::SinatraInstrumentation::Chain
      end

      ::Sinatra.module_eval do
        register NewRelic::Agent::Instrumentation::Sinatra::Ignorer
      end

      prepend_instrument ::Sinatra::Base, NewRelic::Agent::Instrumentation::SinatraInstrumentation::Prepend
      
    else
      chain_instrument NewRelic::Agent::Instrumentation::SinatraInstrumentation::Chain
    end


  end

  # had to keep this chunk in an executes block bc rack
  executes do 
    if Sinatra::Base.respond_to?(:build)
      # These requires are inside an executes block because they require rack, and
      # we can't be sure that rack is available when this file is first required.
      require 'new_relic/rack/agent_hooks'
      require 'new_relic/rack/browser_monitoring'
      if use_prepend?
        ::Sinatra::Base.prepend NewRelic::Agent::Instrumentation::SinatraInstrumentation::PrependBuild
      else
        ::Sinatra::Base.class_eval do
          class << self
            def build_with_newrelic(*args, &block)
              build_with_tracing(*args) do 
                build_without_newrelic(*args, &block)
              end
            end
            alias build_without_newrelic build
            alias build build_with_newrelic
          end
        end
      end
    else
      ::NewRelic::Agent.logger.info("Skipping auto-injection of middleware for Sinatra - requires Sinatra 1.2.1+")
    end
  end


end


