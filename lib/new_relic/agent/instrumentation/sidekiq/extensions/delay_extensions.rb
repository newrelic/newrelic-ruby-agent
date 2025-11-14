# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if defined?(Sidekiq::DelayExtensions)
  class Sidekiq::DelayExtensions::GenericJob
    def newrelic_trace_args(msg, queue)
      (target, method_name, *) = ::Sidekiq::DelayExtensions::YAML.unsafe_load(msg['args'][0])

      if target.is_a?(String)
        target = target.constantize
      end

      {
        :name => method_name,
        :class_name => target.class.name,
        :category => 'OtherTransaction/SidekiqJob'
      }
    rescue => e
      NewRelic::Agent.logger.error('Failure during deserializing YAML for Sidekiq::DelayExtensions::GenericJob', e)
      NewRelic::Agent::Instrumentation::Sidekiq::Server.default_trace_args(msg)
    end
  end
end
