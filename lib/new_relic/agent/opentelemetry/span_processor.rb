# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class SpanProcessor
        def on_start(span, parent_context)
          binding.irb
        end

        def on_finish(span)
          binding.irb
        end

        # do we need a force_flush or shutdown?
      end
    end
  end
end
