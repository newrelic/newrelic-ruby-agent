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

        def mark_skip_instrumenting
          @skip_instrumenting = true
        end

        def clear_skip_instrumenting
          @skip_instrumenting = false
        end

        def format_message_with_tracing(severity, datetime, progname, msg)
          formatted_message = yield
          return formatted_message if skip_instrumenting?

          begin
            # It's critical we don't instrumention further logging from our
            # metric recording or we'll stack overflow!!
            mark_skip_instrumenting

            sev = severity || UNKNOWN
            NewRelic::Agent.increment_metric("Logging/lines")
            NewRelic::Agent.increment_metric("Logging/lines/#{sev}")

            size = formatted_message.nil? ? 0 : formatted_message.length
            NewRelic::Agent.record_metric("Logging/size", size)
            NewRelic::Agent.record_metric("Logging/size/#{sev}", size)

            return formatted_message
          ensure
            clear_skip_instrumenting
          end
        end
      end
    end
  end
end
