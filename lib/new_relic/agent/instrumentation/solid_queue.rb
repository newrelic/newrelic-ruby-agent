# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# require 'new_relic/agent/instrumentation/solid_queue_subscriber'

DependencyDetection.defer do
  named :solid_queue

  # depends_on do
  #   !NewRelic::Agent.config[:disable_solid_queue]
  # end

  depends_on do
    defined?(ActiveSupport) &&
      defined?(SolidQueue) &&
      ActiveJob.respond_to?(:gem_version) &&
      ActiveJob.gem_version >= Gem::Version.new('7.1') # support for SolidQueue added in Rails 7.1
      # && !NewRelic::Agent::Instrumentation::SolidQueueSubscriber.subscribed?
  end

  executes do
    NewRelic::Agent.logger.info('Installing SolidQueue instrumentation')
  end

  executes do
    ActiveSupport::Notifications.subscribe(/\A(?:[^\.]+)\.solid_queue\z/,
      NewRelic::Agent::Instrumentation::SolidQueue.new)
  end
end
