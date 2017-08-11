# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class ThroughputMonitor
        def initialize target_samples
          @target = target_samples
          @seen = 0
          @seen_last = 0
          @sampled_count = 0
          @first_cycle = true
          @lock = Mutex.new
        end

        # Called at the beginning of each transaction, increments seen and
        # returns a boolean indicating if we should mark the transaction as
        # sampled. This uses the adaptive sampling algorithm.
        def collect_sample?
          @lock.synchronize do
            collect_sample = if @first_cycle
              @sampled_count < 10
            elsif @sampled_count < @target
              rand(@seen_last) < @target
            else
              rand(@seen) < @target
            end

            @sampled_count += 1 if collect_sample
            @seen += 1

            collect_sample
          end
        end

        def reset
          @lock.synchronize do
            @first_cycle = false
            @seen_last = @seen
            @seen = 0
            @sampled_count = 0
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
      end
    end
  end
end
