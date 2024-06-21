# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module LogStasher::Prepend
    include NewRelic::Agent::Instrumentation::LogStasher

    def build_logstash_event(data, tags)
      build_logstash_event_with_new_relic(data, tags) { super }
    end
  end
end
