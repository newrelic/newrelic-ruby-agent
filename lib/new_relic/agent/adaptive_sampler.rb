# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class AdaptiveSampler

      def initialize target_samples = 10, interval_duration = 60
        @target = target_samples
        @seen = 0
        @seen_last = 0
        @sampled_count = 0
        @interval_duration = interval_duration
        @first_interval = true
        @interval_start = Time.now.to_f
        @lock = Mutex.new
        register_config_callbacks
      end

      # Called at the beginning of each transaction, increments seen and
      # returns a boolean indicating if we should mark the transaction as
      # sampled. This uses the adaptive sampling algorithm.
      def sampled?
        @lock.synchronize do
          reset_if_interval_expired!
          sampled = if @first_interval
            @sampled_count < 10
          elsif @sampled_count < @target
            rand(@seen_last) < @target
          else
            rand(@seen) < (@target ** (@target / @sampled_count) - @target ** 0.5)
          end

          @sampled_count += 1 if sampled
          @seen += 1

          sampled
        end
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

      def reset_if_interval_expired!
        now = Time.now.to_f
        return unless @interval_start + @interval_duration <= now

        elapsed_intervals = Integer((now - @interval_start) / @interval_duration)
        @interval_start = @interval_start + elapsed_intervals * @interval_duration

        @first_interval = false
        @seen_last = elapsed_intervals > 1 ? 0 : @seen
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
            NewRelic::Agent.logger.debug "Sampling target set to: #{target}"
          end
        end
      end

      def register_sampling_period_callback
        NewRelic::Agent.config.register_callback(:sampling_target_period_in_seconds) do |period|
          period_changed = false
          @lock.synchronize do
            if @interval_duration != period
              @interval_duration = period
              period_changed = true
            end
          end
          if period_changed
            NewRelic::Agent.logger.debug "Sampling period set to: #{period}"
          end
        end
      end
    end
  end
end
