# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require_relative 'sidekiq/client'
require_relative 'sidekiq/server'
require_relative 'sidekiq/extensions/delayed_class'

DependencyDetection.defer do
  @name = :sidekiq

  depends_on do
    defined?(::Sidekiq) && !NewRelic::Agent.config[:disable_sidekiq]
  end

  executes do
    ::NewRelic::Agent.logger.info('Installing Sidekiq instrumentation')
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
        chain.add(NewRelic::Agent::Instrumentation::Sidekiq::Server)
      end

      if config.respond_to?(:error_handlers)
        config.error_handlers << proc do |error, *_|
          NewRelic::Agent.notice_error(error)
        end
      end
    end
  end

  executes do
    next unless Gem::Version.new(Sidekiq::VERSION) < Gem::Version.new('5.0.0')

    deprecation_msg = 'Instrumentation for Sidekiq versions below 5.0.0 is deprecated.' \
      'They will stop being monitored in version 9.0.0. ' \
      'Please upgrade your Sidekiq version to continue receiving full support. '

    ::NewRelic::Agent.logger.log_once(
      :warn,
      :deprecated_sidekiq_version,
      deprecation_msg
    )

    ::NewRelic::Agent.record_metric("Supportability/Deprecated/Sidekiq", 1)
  end
end
