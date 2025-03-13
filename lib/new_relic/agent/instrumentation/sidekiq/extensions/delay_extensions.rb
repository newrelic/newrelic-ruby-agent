# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if defined?(Sidekiq::DelayExtensions)
  class Sidekiq::DelayExtensions::GenericJob
    def newrelic_trace_args(msg, queue)
      # puts '**********'
      # puts "msg: #{msg}"
      # puts "queue: #{queue}"
      # puts '**********'
      (target, method_name, *) = ::Sidekiq::DelayExtensions::YAML.unsafe_load(msg['args'][0])

      if target.is_a?(String)
        target = target.constantize
      end

      # puts '--------------'
      # puts "name: #{method_name}"
      # puts "class name: #{target.name}"
      # puts '--------------'

      {
        :name => method_name,
        :class_name => target.name,
        :category => 'OtherTransaction/SidekiqJob'
      }
    rescue => e
      NewRelic::Agent.logger.error('Failure during deserializing YAML for Sidekiq::DelayExtensions::GenericJob', e)
      NewRelic::Agent::Instrumentation::Sidekiq::Server.default_trace_args(msg)
    end
  end
end
