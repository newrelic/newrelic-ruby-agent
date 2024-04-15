# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Logstasher

    def build_logstash_event_with_new_relic(data,tags)
      # add instrumentation content here
      yield
    end
  end
end
