# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/action_cable_subscriber'

DependencyDetection.defer do
  @name = :rails5_action_cable

  depends_on do
    defined?(::Rails) &&
     ::Rails::VERSION::MAJOR.to_i == 5 &&
       defined?(::ActionCable)
  end

  depends_on do
    !NewRelic::Agent.config[:disable_action_cable_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActionCableSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 5 ActionCable Instrumentation'
  end

  executes do
    ActiveSupport::Notifications.subscribe('perform_action.action_cable',
      NewRelic::Agent::Instrumentation::ActionCableSubscriber.new)
  end
end
