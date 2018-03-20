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
            rand(@seen) < (@target ** (@target / @sampled_count) - @target ** 0.51)
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
    end
  end
end
