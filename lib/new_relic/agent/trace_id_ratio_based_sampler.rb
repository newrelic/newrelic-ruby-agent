# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    # Bring in the OTel sampling process as much as possible
    class TraceIdRatioBasedSampler
      attr_reader :sampler

      def initialize(ratio: nil, sampler: 'root')
        @ratio = nil
        @sampler = sampler
        @id_upper_bound = (ratio * (2**64 - 1)).ceil
      end

      # copied from otel, not sure if we need this
      # def ==(other)
      #   @sampler == other.sampler
      # end

      # trace Id
      # parent context
      # def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
      #   tracestate = OpenTelemetry::Trace.current_span(parent_context).context.tracestate
      #   if sample?(trace_id)
      #     Result.new(decision: Decision::RECORD_AND_SAMPLE, tracestate: tracestate)
      #   else
      #     Result.new(decision: Decision::DROP, tracestate: tracestate)
      #   end
      # end
      def should_sample?(payload, trace_flags)
        tracestate = OpenTelemetry::Trace.current_span(parent_context).context.tracestate
        if sample?(trace_id)
          Result.new(decision: Decision::RECORD_AND_SAMPLE, tracestate: tracestate)
        else
          Result.new(decision: Decision::DROP, tracestate: tracestate)
        end
      end


      def sample?(trace_id)
        @ratio == 1.0 || trace_id[8, 8].unpack1('Q>') < @id_upper_bound
      end

      def sampled?
      end

      def exponential_backoff
        @target**(@target.to_f / @sampled_count) - @target**0.5
      end

      def stats
        @lock.synchronize do
          {
            target: @target,
            seen: @seen,
            seen_last: @seen_last,
            sampled_count: @sampled_count
          }
        end
      end

      private

      def reset_if_period_expired!
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return unless @period_start + @period_duration <= now

        elapsed_periods = Integer((now - @period_start) / @period_duration)
        @period_start += elapsed_periods * @period_duration

        @first_period = false
        @seen_last = elapsed_periods > 1 ? 0 : @seen
        @seen = 0
        @sampled_count = 0
      end

      def register_config_callbacks
        register_sampling_target_callback
        register_sampling_period_callback
      end

      def register_sampling_target_callback
        NewRelic::Agent.config.register_callback(:sampling_target) do |target|
          target_changed = false
          @lock.synchronize do
            if @target != target
              @target = target
              target_changed = true
            end
          end
          if target_changed
            NewRelic::Agent.logger.debug("Sampling target set to: #{target}")
          end
        end
      end

      def register_sampling_period_callback
        NewRelic::Agent.config.register_callback(:sampling_target_period_in_seconds) do |period_duration|
          period_changed = false
          @lock.synchronize do
            if @period_duration != period_duration
              @period_duration = period_duration
              period_changed = true
            end
          end
          if period_changed
            NewRelic::Agent.logger.debug("Sampling period set to: #{period_duration}")
          end
        end
      end
    end
  end
end
