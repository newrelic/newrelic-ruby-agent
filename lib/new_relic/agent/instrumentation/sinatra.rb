# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/instrumentation/controller_instrumentation'
require 'new_relic/agent/instrumentation/sinatra/transaction_namer'
require 'new_relic/agent/instrumentation/sinatra/ignorer'
require 'new_relic/agent/parameter_filtering'

require_relative 'sinatra/chain'

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
      chain_instrument NewRelic::Agent::Instrumentation::SinatraInstrumentation::Chain
      
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

      ::Sinatra::Base.class_eval do
        class << self
          alias build_without_newrelic build
          alias build build_with_newrelic
        end
      end
    else
      ::NewRelic::Agent.logger.info("Skipping auto-injection of middleware for Sinatra - requires Sinatra 1.2.1+")
    end
  end


end


