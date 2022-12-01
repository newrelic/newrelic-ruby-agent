# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'concurrent_ruby/instrumentation'
require_relative 'concurrent_ruby/chain'
require_relative 'concurrent_ruby/prepend'

DependencyDetection.defer do
  named :'concurrent_ruby'

  depends_on do
    # The class that needs to be defined to prepend/chain onto. This can be used
    # to determine whether the library is installed.
    defined?(::Concurrent)
    # Add any additional requirements to verify whether this instrumentation
    # should be installed
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing concurrent_ruby instrumentation')

    if use_prepend?
      prepend_instrument ::Concurrent, NewRelic::Agent::Instrumentation::ConcurrentRuby::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::ConcurrentRuby
    end
  end
end
