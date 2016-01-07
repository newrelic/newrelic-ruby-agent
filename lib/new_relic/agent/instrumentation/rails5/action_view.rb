# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/action_view_subscriber'

DependencyDetection.defer do
  @name = :rails5_view

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 5
  end

  depends_on do
    !NewRelic::Agent.config[:disable_view_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 5 view instrumentation'
  end

  executes do
    NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribe(/render_.+\.action_view$/)
  end
end
