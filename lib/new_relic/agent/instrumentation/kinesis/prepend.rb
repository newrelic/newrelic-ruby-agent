# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Kinesis::Prepend
    include NewRelic::Agent::Instrumentation::Kinesis

    INSTRUMENTED_METHODS.each do |method_name|
      define_method(method_name) do |*args|
        instrument_method_with_new_relic(method_name, *args) { super(*args) }
      end
    end

    def build_request(*args)
      build_request_with_new_relic(*args) { super }
    end
  end
end
