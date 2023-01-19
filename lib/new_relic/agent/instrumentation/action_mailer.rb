# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/action_mailer_subscriber'

DependencyDetection.defer do
  named :action_mailer

  depends_on do
    defined?(ActiveSupport) &&
      defined?(ActionMailer) &&
      ActionMailer.respond_to?(:gem_version) &&
      ActionMailer.gem_version >= Gem::Version.new('5.0') &&
      !NewRelic::Agent::Instrumentation::ActionMailerSubscriber.subscribed?
  end

  executes do
    NewRelic::Agent.logger.info('Installing ActionMailer instrumentation')
  end

  executes do
    ActiveSupport::Notifications.subscribe(/\A(?:[^\.]+)\.action_mailer\z/,
      NewRelic::Agent::Instrumentation::ActionMailerSubscriber.new)

    # ActiveSupport::Notifications.subscribe(/\A(?:[^\.]+)\.action_mailer\z/) do |name, start, finish, id, payload|
    # end
  end
end
