# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class TransactionSampleBuffer
        attr_reader :samples

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
            @samples << sample
            truncate_samples_if_needed
          end
        end

        def store_previous(previous_samples)
          return unless enabled?
          previous_samples.each do |sample|
            @samples << sample if allow_sample?(sample)
          end
          truncate_samples_if_needed
        end

        def truncate_samples_if_needed
          if @samples.length > max_samples
            truncate_samples
          end
        end

        # Our default truncation strategy is to keep max_samples worth of the
        # longest samples. Override this method for alternate behavior.
        def truncate_samples
          @samples = @samples.sort_by {|s| s.duration}.last(max_samples)
        end

        # When pushing a scope different sample buffers potentially want to
        # know about what's happening to annotate the incoming segments
        def visit_segment(*)
          # no-op
        end
      end
    end
  end
end
