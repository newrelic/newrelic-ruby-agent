# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module MethodTracerHelpers
      MAX_ALLOWED_METRIC_DURATION = 1_000_000_000 # roughly 31 years

      extend self

      # helper for logging errors to the newrelic_agent.log
      # properly. Logs the error at error level
      def log_errors(code_area)
        yield
      rescue => e
        ::NewRelic::Agent.logger.error("Caught exception in #{code_area}.", e)
      end

      def trace_execution_scoped_header(state, t0)
        log_errors(:trace_execution_scoped_header) do
          stack = state.traced_method_stack
          stack.push_frame(state, :method_tracer, t0)
        end
      end

      def record_metrics(state, first_name, other_names, duration, exclusive, options)
        record_scoped_metric = options.has_key?(:scoped_metric) ? options[:scoped_metric] : true
        stat_engine = NewRelic::Agent.instance.stats_engine
        if record_scoped_metric
          stat_engine.record_scoped_and_unscoped_metrics(state, first_name, other_names, duration, exclusive)
        else
          metrics = [first_name].concat(other_names)
          stat_engine.record_unscoped_metrics(state, metrics, duration, exclusive)
        end
      end

      def trace_execution_scoped_footer(state, t0, first_name, metric_names, expected_frame, options, t1=Time.now.to_f)
        log_errors(:trace_method_execution_footer) do
          if expected_frame
            stack = state.traced_method_stack
            create_metrics = options.has_key?(:metric) ? options[:metric] : true
            frame = stack.pop_frame(state, expected_frame, first_name, t1, create_metrics)
            if create_metrics
              duration = t1 - t0
              exclusive = duration - frame.children_time

              if duration < MAX_ALLOWED_METRIC_DURATION
                if duration < 0
                  ::NewRelic::Agent.logger.log_once(:warn, "metric_duration_negative:#{first_name}",
                    "Metric #{first_name} has negative duration: #{duration} s")
                end

                if exclusive < 0
                  ::NewRelic::Agent.logger.log_once(:warn, "metric_exclusive_negative:#{first_name}",
                    "Metric #{first_name} has negative exclusive time: duration = #{duration} s, child_time = #{frame.children_time}")
                end

                record_metrics(state, first_name, metric_names, duration, exclusive, options)
              else
                ::NewRelic::Agent.logger.log_once(:warn, "too_huge_metric:#{first_name}",
                  "Ignoring metric #{first_name} with unacceptably large duration: #{duration} s")
              end
            end
          end
        end
      end

      def trace_execution_scoped(metric_names, options={}) #THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::TransactionState.tl_get
        return yield unless state.is_execution_traced?

        metric_names = Array(metric_names)
        first_name   = metric_names.shift
        return yield unless first_name

        additional_metrics_callback = options[:additional_metrics_callback]
        start_time = Time.now.to_f
        expected_scope = trace_execution_scoped_header(state, start_time)

        begin
          result = yield
          metric_names += Array(additional_metrics_callback.call) if additional_metrics_callback
          result
        ensure
          trace_execution_scoped_footer(state, start_time, first_name, metric_names, expected_scope, options)
        end
      end

    end
  end
end
