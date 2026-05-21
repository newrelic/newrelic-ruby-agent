# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/rails_event_log_subscriber'

DependencyDetection.defer do
  named :rails_event_logger

  # Check for Rails.event (Rails 8.1+)
  depends_on do
    defined?(Rails) &&
      Rails.respond_to?(:event) &&
      Rails.event.respond_to?(:subscribe)
  end

  # Check if logging and instrumentation are enabled
  depends_on do
    NewRelic::Agent.config[:'application_logging.enabled'] &&
      NewRelic::Agent.config[:'instrumentation.rails_event_logger']
  end

  # Prevent duplicate subscription
  depends_on do
    !NewRelic::Agent::Instrumentation::RailsEventLogSubscriber.subscribed?
  end

  executes do
    NewRelic::Agent.logger.info('Installing Rails.event logging instrumentation')
    # Subscribe to Rails.event system
    subscriber = NewRelic::Agent::Instrumentation::RailsEventLogSubscriber.new
    Rails.event.subscribe(subscriber)

    event_names = NewRelic::Agent.config[:'instrumentation.rails_event_logger.event_names']
    if event_names.empty?
      NewRelic::Agent.logger.debug('Subscribed to ALL Rails.event notifications')
    else
      NewRelic::Agent.logger.debug("Subscribed to Rails.event notifications: #{event_names.join(', ')}")
    end
  end
end
