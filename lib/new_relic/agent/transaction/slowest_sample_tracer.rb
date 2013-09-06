# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class SlowestSampleTracer
        attr_accessor :slowest_sample

        def initialize
          @slowest_sample = nil
        end

        def reset!
          @slowest_sample = nil
        end

        NO_SAMPLES = [].freeze

        def harvest_samples
          @slowest_sample ? [@slowest_sample] : NO_SAMPLES
        ensure
          reset!
        end

        def store(sample)
          if slower_sample?(sample) && exceeds_threshold?(sample)
            @slowest_sample = sample
          end
        end

        def slower_sample?(new_sample)
          @slowest_sample.nil? || (new_sample.duration > @slowest_sample.duration)
        end

        def exceeds_threshold?(sample)
          sample.threshold && sample.duration >= sample.threshold
        end

        def visit_segment(*)
          # no op
        end
      end
    end
  end
end
