# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'thread/chain'
require_relative 'thread/prepend'

DependencyDetection.defer do
  named :thread

  depends_on do
    defined?(Thread)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Thread Instrumentation'
  end

  executes do
    if use_prepend?
      prepend_instrument ::Thread.singleton_class, ::NewRelic::Agent::Instrumentation::Thread::Prepend
    else
      chain_instrument ::NewRelic::Agent::Instrumentation::Thread::Chain
    end
  end
end
