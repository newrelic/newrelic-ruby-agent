# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class TransactionSampleBuffer
        attr_reader :samples

        SINGLE_BUFFER_MAX = 20
        NO_SAMPLES = [].freeze

        def initialize
          @samples = []
        end

        def enabled?
          true
        end

        def reset!
          @samples = []
        end

        def harvest_samples
          @samples
        ensure
          reset!
        end

        def allow_sample?(sample)
          true
        end

        def store(sample)
          return unless enabled?
          if allow_sample?(sample)
            add_sample(sample)
            truncate_samples_if_needed
          end
        end

        def store_previous(previous_samples)
          return unless enabled?
          previous_samples.each do |sample|
            add_sample(sample) if allow_sample?(sample)
          end
          truncate_samples_if_needed
        end

        def truncate_samples_if_needed
          truncate_samples if full?
        end

        def full?
          @samples.length >= effective_max_samples
        end

        # To keep users from consuming too much memory, we apply an upper limit
        # per buffer to how large it can get...
        def effective_max_samples
          max_samples > SINGLE_BUFFER_MAX ? SINGLE_BUFFER_MAX : max_samples
        end

        # Our default truncation strategy is to keep effective_max_samples
        # worth of the longest samples. Override this method for alternate
        # behavior.
        #
        # This doesn't use the more convenient #last and #sort_by to avoid
        # additional array allocations (and abundant alliteration)
        def truncate_samples
          @samples.sort!{|a,b| a.duration <=> b.duration}
          @samples.slice!(0..-(effective_max_samples + 1))
        end

        # When pushing a scope different sample buffers potentially want to
        # know about what's happening to annotate the incoming segments
        def visit_segment(*)
          # no-op
        end

        private

        # If a buffer needs to modify an added sample, override this method.
        # Bounds checking, allowing samples and truncation belongs elsewhere.
        def add_sample(sample)
          @samples << sample
        end

      end
    end
  end
end
