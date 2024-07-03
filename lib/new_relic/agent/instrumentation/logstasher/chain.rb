# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module LogStasher::Chain
    def self.instrument!
      ::LogStasher.singleton_class.class_eval do
        include NewRelic::Agent::Instrumentation::LogStasher

        alias_method(:build_logstash_event_without_new_relic, :build_logstash_event)

        def build_logstash_event(data, tags)
          build_logstash_event_with_new_relic(data, tags) do
            build_logstash_event_without_new_relic(data, tags)
          end
        end
      end
    end
  end
end
