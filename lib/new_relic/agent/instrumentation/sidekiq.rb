# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq/client'
require_relative 'sidekiq/server'
require_relative 'sidekiq/extensions/delayed_class'
require_relative 'sidekiq/extensions/delay_extensions'

DependencyDetection.defer do
  @name = :sidekiq

  depends_on do
    defined?(Sidekiq) && !NewRelic::Agent.config[:disable_sidekiq]
  end

  executes do
    NewRelic::Agent.logger.info('Installing Sidekiq instrumentation')
  end

  executes do
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add(NewRelic::Agent::Instrumentation::Sidekiq::Client)
      end
    end

    Sidekiq.configure_server do |config|
      config.client_middleware do |chain|
        chain.add(NewRelic::Agent::Instrumentation::Sidekiq::Client)
      end
      config.server_middleware do |chain|
        # We started prepending v chaining NR middleware in 9.18.0 in response to:
        # https://github.com/newrelic/newrelic-ruby-agent/issues/3037
        # This way, exceptions resolved by Sidekiq's own middleware are not reported in the agent
        if chain.respond_to?(:prepend)
          chain.prepend(NewRelic::Agent::Instrumentation::Sidekiq::Server)
        else
          chain.add(NewRelic::Agent::Instrumentation::Sidekiq::Server)
        end
      end

      if config.respond_to?(:error_handlers) && !NewRelic::Agent.config[:'sidekiq.ignore_retry_errors']
        # Sidekiq 3.0.0 - 7.1.4 expect error_handlers to have 2 arguments
        # Sidekiq 7.1.5+ expect error_handlers to have 3 arguments
        config.error_handlers << proc do |error, _ctx, *_|
          NewRelic::Agent.notice_error(error)
        end
      end

      if config.respond_to?(:death_handlers) && NewRelic::Agent.config[:'sidekiq.ignore_retry_errors']
        config.death_handlers << proc do |_, error|
          NewRelic::Agent.notice_error(error)
        end
      end
    end
  end
end
