# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/rack'
require 'new_relic/rack/error_collector'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/developer_mode'
require 'new_relic/rack/browser_monitoring'

DependencyDetection.defer do
  depends_on do
    [ defined?(::Rack),
      defined?(::Rack::Builder),
      defined?(::NewRelic::Rack::AgentHooks),
      defined?(::NewRelic::Rack::DeveloperMode),
      defined?(::NewRelic::Rack::BrowserMonitoring),
      defined?(::NewRelic::Rack::ErrorCollector) ].all?
  end

  executes do
      middleware_classes = [
        ::NewRelic::Rack::ErrorCollector,
        ::NewRelic::Rack::AgentHooks,
        ::NewRelic::Rack::DeveloperMode,
        ::NewRelic::Rack::BrowserMonitoring
      ]

      middleware_classes.each do |middleware_class|
        ::NewRelic::Agent::Instrumentation::RackBuilder.add_new_relic_tracing_to_middleware(middleware_class)
      end
  end
end

