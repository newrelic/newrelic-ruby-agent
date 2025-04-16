# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        require_relative 'trace/tracer_provider'
        require_relative 'trace/tracer'
        require_relative 'trace/fake_span'
      end
    end
  end
end
