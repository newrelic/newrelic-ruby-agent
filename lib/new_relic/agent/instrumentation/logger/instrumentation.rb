# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Logger
        def skip_instrumenting?
          defined?(@skip_instrumenting) && @skip_instrumenting
        end

        def format_message_with_tracing(severity, datetime, progname, msg)
          return yield if skip_instrumenting?

          begin
            # It's critical we don't instrumention further logging from our
            # metric recording or we'll stack overflow!!
            @skip_instrumenting = true

            sev = severity || UNKNOWN
            NewRelic::Agent.increment_metric("Logging/lines")
            NewRelic::Agent.increment_metric("Logging/lines/#{sev}")

            size = msg.nil? ? 0 : msg.length
            NewRelic::Agent.record_metric("Logging/size", size)
            NewRelic::Agent.record_metric("Logging/size/#{sev}", size)

            yield
          ensure
            @skip_instrumenting = false
          end
        end
      end
    end
  end
end
