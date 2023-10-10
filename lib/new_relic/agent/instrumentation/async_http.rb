# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'async_http/instrumentation'
require_relative 'async_http/chain'
require_relative 'async_http/prepend'

DependencyDetection.defer do
  named :'async_http'

  depends_on do
    # The class that needs to be defined to prepend/chain onto. This can be used
    # to determine whether the library is installed.
    defined?(Async::Http)
    # Add any additional requirements to verify whether this instrumentation
    # should be installed
  end

  executes do
    NewRelic::Agent.logger.info('Installing async_http instrumentation')

    if use_prepend?
      prepend_instrument Async::Http, NewRelic::Agent::Instrumentation::AsyncHttp::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::AsyncHttp::Chain
    end
  end
end
