# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/action_view_subscriber'
require 'new_relic/agent/prepend_supportability'

DependencyDetection.defer do
  @name = :rails4_view

  depends_on do
    defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    !NewRelic::Agent.config[:disable_view_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 4 view instrumentation'
  end

  executes do
    NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribe(/render_.+\.action_view$/)
    NewRelic::Agent::PrependSupportability.record_metrics_for(::ActionView::Base, ::ActionView::Template, ::ActionView::Renderer)
  end
end
