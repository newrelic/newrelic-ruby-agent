# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/custom_events_subscriber'
require 'new_relic/agent/prepend_supportability'

DependencyDetection.defer do
  @name = :custom_event_notifications

  depends_on do
    binding.irb
    defined?(::Rails::VERSION::MAJOR) &&
      ::Rails::VERSION::MAJOR.to_i >= 5 &&
      defined?(::ActiveSupport::Notifications) &&
      defined?(::ActiveSupport::IsolatedExecutionState)
  end

  depends_on do
    binding.irb
    !::NewRelic::Agent.config[:disable_custom_events_instrumentation] &&
      !::NewRelic::Agent.config[:custom_events_instrumentation_topics].empty? &&
      !::NewRelic::Agent::Instrumentation::CustomEventsSubscriber.subscribed?
  end

  executes do
    binding.irb
    ::NewRelic::Agent.logger.info('Installing notifications based ActiveSupport custom events instrumentation')
  end

  executes do
    binding.irb
    ::NewRelic::Agent.config[:custom_events_instrumentation_topics].each do |topic|
      ::ActiveSupport::Notifications.subscribe(topic, NewRelic::Agent::Instrumentation::CustomEventsSubscriber.new)
    end
  end
end
