# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# TODO: do we want to nest everything within a Trace namespace?
module NewRelic
  module Agent
    module OpenTelemetry
      class Span
        def set_attribute(key, value)
          binding.irb
        end
      end
    end
  end
end
