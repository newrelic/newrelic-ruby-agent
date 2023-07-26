# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'roda/instrumentation'
require_relative 'roda/chain'
require_relative 'roda/prepend'

DependencyDetection.defer do
  named :roda

  depends_on do
    defined?(Roda) &&
      Gem::Version.new(Roda::RodaVersion) >= '3.19.0' &&
      Roda::RodaPlugins::Base::ClassMethods.private_method_defined?(:build_rack_app) &&
      Roda::RodaPlugins::Base::InstanceMethods.method_defined?(:_roda_handle_main_route)
  end

  executes do
    # These requires are inside an executes block because they require rack, and
    # we can't be sure that rack is available when this file is first required.
    require 'new_relic/rack/agent_hooks'
    require 'new_relic/rack/browser_monitoring'
    if use_prepend?
      prepend_instrument Roda.singleton_class, NewRelic::Agent::Instrumentation::Roda::Build::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Roda::Build::Chain
    end
  end

  executes do
    NewRelic::Agent.logger.info('Installing roda instrumentation')

    if use_prepend?
      prepend_instrument Roda, NewRelic::Agent::Instrumentation::Roda::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Roda::Chain
    end
  end
end
