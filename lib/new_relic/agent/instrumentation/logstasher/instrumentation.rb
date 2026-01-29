# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module LogStasher
    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

    def self.enabled?
      NewRelic::Agent.config[:'instrumentation.logstasher'] != 'disabled'
    end

    def build_logstash_event_with_new_relic(*args)
      logstasher_event = yield
      log = logstasher_event.instance_variable_get(:@data)

      ::NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)
      ::NewRelic::Agent.agent.log_event_aggregator.record_logstasher_event(log)
      log['message'] = ::NewRelic::Agent::LocalLogDecorator.decorate(log['message'])

      logstasher_event
    end
  end
end
