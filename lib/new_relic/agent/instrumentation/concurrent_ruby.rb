# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'concurrent_ruby/instrumentation'
require_relative 'concurrent_ruby/chain'
require_relative 'concurrent_ruby/prepend'

DependencyDetection.defer do
  named :'concurrent_ruby'

  depends_on do
    defined?(::Concurrent)
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing concurrent-ruby instrumentation')

    if use_prepend?
      prepend_instrument ::Concurrent::Promises::FactoryMethods, NewRelic::Agent::Instrumentation::ConcurrentRuby::Prepend
      # TODO: let's use separate classes
      prepend_instrument ::Concurrent::ExecutorService, NewRelic::Agent::Instrumentation::ConcurrentRuby::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::ConcurrentRuby
    end
  end
end
