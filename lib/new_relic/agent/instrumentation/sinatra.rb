# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sinatra/transaction_namer'
require_relative 'sinatra/ignorer'
require_relative 'sinatra/instrumentation'
require_relative 'sinatra/chain'
require_relative 'sinatra/prepend'

DependencyDetection.defer do
  named :sinatra

  depends_on { defined?(Sinatra) && defined?(Sinatra::Base) }
  depends_on { Sinatra::Base.private_method_defined?(:dispatch!) }
  depends_on { Sinatra::Base.private_method_defined?(:process_route) }
  depends_on { Sinatra::Base.private_method_defined?(:route_eval) }

  executes do
    if use_prepend?
      prepend_instrument Sinatra::Base, NewRelic::Agent::Instrumentation::Sinatra::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Sinatra::Chain
    end

    Sinatra::Base.class_eval { register NewRelic::Agent::Instrumentation::Sinatra::Ignorer }
    Sinatra.module_eval { register NewRelic::Agent::Instrumentation::Sinatra::Ignorer }
  end

  executes do
    # These requires are inside an executes block because they require rack, and
    # we can't be sure that rack is available when this file is first required.
    require 'new_relic/rack/agent_hooks'
    require 'new_relic/rack/browser_monitoring'
    if use_prepend?
      prepend_instrument Sinatra::Base.singleton_class, NewRelic::Agent::Instrumentation::Sinatra::Build::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Sinatra::Build::Chain
    end
  end
end
