# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/action_controller_subscriber'


DependencyDetection.defer do
  @name = :rails4_controller

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    defined?(ActionController) && defined?(ActionController::Base)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 4 Controller instrumentation'
  end

  executes do
    class ActionController::Base
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    end
    NewRelic::Agent::Instrumentation::ActionControllerSubscriber \
      .subscribe(/^process_action.action_controller$/)
  end
end
