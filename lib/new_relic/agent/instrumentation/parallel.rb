# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'parallel/instrumentation'
require_relative 'parallel/chain'
require_relative 'parallel/prepend'

DependencyDetection.defer do
  @name = :parallel

  depends_on do
    defined?(Parallel) &&
      NewRelic::LanguageSupport.can_fork?
  end

  executes do
    NewRelic::Agent.logger.info('Installing Parallel instrumentation')

    # Start the pipe channel listener to receive data from forked workers
    NewRelic::Agent::PipeChannelManager.listener.start unless NewRelic::Agent::PipeChannelManager.listener.started?

    if use_prepend?
      prepend_instrument Parallel.singleton_class, NewRelic::Agent::Instrumentation::Parallel::Prepend
    else
      NewRelic::Agent::Instrumentation::Parallel::Chain.instrument!
    end
  end
end
