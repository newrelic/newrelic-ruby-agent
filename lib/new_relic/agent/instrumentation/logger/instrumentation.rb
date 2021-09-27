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

        LINES = "Logging/lines".freeze
        SIZE = "Logging/size".freeze

        def line_metric_name_by_severity(sev)
          @line_metrics ||= {}
          @line_metrics[sev] ||= "Logging/lines/#{sev}".freeze
        end

        def size_metric_name_by_severity(sev)
          @size_metrics ||= {}
          @size_metrics[sev] ||= "Logging/size/#{sev}".freeze
        end


        def format_message_with_tracing(severity, datetime, progname, msg)
          formatted_message = yield
          return formatted_message if skip_instrumenting?

          begin
            # It's critical we don't instrumention further logging from our
            # metric recording in the agent itself or we'll stack overflow!!
            mark_skip_instrumenting

            sev = severity || UNKNOWN
            NewRelic::Agent.increment_metric(LINES)
            NewRelic::Agent.increment_metric(line_metric_name_by_severity(sev))

            size = formatted_message.nil? ? 0 : formatted_message.length
            NewRelic::Agent.record_metric(SIZE, size)
            NewRelic::Agent.record_metric(size_metric_name_by_severity(sev), size)

            return formatted_message
          ensure
            clear_skip_instrumenting
          end
        end
      end
    end
  end
end
