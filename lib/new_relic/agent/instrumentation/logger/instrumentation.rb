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

        def line_metric_name_by_severity(severity)
          @line_metrics ||= {}
          @line_metrics[severity] ||= "Logging/lines/#{severity}".freeze
        end

        def size_metric_name_by_severity(severity)
          @size_metrics ||= {}
          @size_metrics[severity] ||= "Logging/size/#{severity}".freeze
        end

        def format_message_with_tracing(severity, datetime, progname, msg)
          ### DEBUG
          if severity == 'ERROR'
            puts "\n\n\n\n\n\n\n\n\nDEBUG BACKTRACE:\n#{caller.join("\n")}\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
          end

          formatted_message = yield
          return formatted_message if skip_instrumenting?

          begin
            # It's critical we don't instrument logging from metric recording
            # methods within NewRelic::Agent, or we'll stack overflow!!
            mark_skip_instrumenting

            NewRelic::Agent.increment_metric(LINES)
            NewRelic::Agent.increment_metric(line_metric_name_by_severity(severity))

            size = formatted_message.nil? ? 0 : formatted_message.bytesize
            NewRelic::Agent.record_metric(SIZE, size)
            NewRelic::Agent.record_metric(size_metric_name_by_severity(severity), size)

            return formatted_message
          ensure
            clear_skip_instrumenting
          end
        end
      end
    end
  end
end
