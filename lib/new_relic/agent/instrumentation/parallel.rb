# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'parallel/instrumentation'
require_relative 'parallel/chain'
require_relative 'parallel/prepend'

DependencyDetection.defer do
  @name = :parallel

  depends_on do
    defined?(::Parallel) &&
      NewRelic::LanguageSupport.can_fork?
  end

  executes do
    NewRelic::Agent.logger.info('Installing Parallel instrumentation')

    # Ensure the agent is started and the pipe channel listener is running
    # This is similar to what Resque does in its before_first_fork hook
    if NewRelic::Agent.agent&.started?
      # Agent already started, just ensure the listener is started
      NewRelic::Agent::PipeChannelManager.listener.start unless NewRelic::Agent::PipeChannelManager.listener.started?
    else
      # Agent not started yet, start it with the listener
      NewRelic::Agent.manual_start(:start_channel_listener => true)
    end

    if use_prepend?
      prepend_instrument ::Parallel.singleton_class, NewRelic::Agent::Instrumentation::Parallel::Prepend
    else
      NewRelic::Agent::Instrumentation::Parallel::Chain.instrument!
    end
  end
end
