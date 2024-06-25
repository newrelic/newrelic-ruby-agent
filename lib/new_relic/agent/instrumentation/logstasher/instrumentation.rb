# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module LogStasher
    INSTRUMENTATION_NAME = 'LogStasher'

    def self.enabled?
      NewRelic::Agent.config[:'instrumentation.logstasher'] != 'disabled'
    end

    def build_logstash_event_with_new_relic(data, _tags)
      data = yield
      log = data.instance_variable_get(:@data)

      ::NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
      ::NewRelic::Agent.agent.log_event_aggregator.record_json(log)
      ::NewRelic::Agent::LocalLogDecorator.decorate(log)

      data
    end
  end
end
