# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

DependencyDetection.defer do
  @name = :rainbows

  depends_on do
    defined?(::Rainbows) && defined?(::Rainbows::HttpServer)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rainbows instrumentation'
    ::NewRelic::Agent.logger.info 'Detected Rainbows, please see additional documentation: https://newrelic.com/docs/troubleshooting/im-using-unicorn-and-i-dont-see-any-data'

    deprecation_msg = 'The dispatcher rainbows is deprecated. It will be removed ' \
     'in version 9.0.0. Please use a supported dispatcher instead. ' \
     'Visit https://docs.newrelic.com/docs/apm/agents/ruby-agent/getting-started/ruby-agent-requirements-supported-frameworks for options.'

    ::NewRelic::Agent.logger.log_once(
      :warn,
      :deprecated_rainbows_dispatcher,
      deprecation_msg
    )
    ::NewRelic::Agent.record_metric("Supportability/Deprecated/Rainbows", 1)
  end

  executes do
    Rainbows::HttpServer.class_eval do
      old_worker_loop = instance_method(:worker_loop)
      define_method(:worker_loop) do |worker|
        NewRelic::Agent.after_fork(:force_reconnect => true)
        old_worker_loop.bind(self).call(worker)
      end
    end
  end
end
