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
          @samples << sample if allow_sample?(sample)
          truncate_samples
        end

        def sort_for_truncation
          @default_sort_for_truncation ||= Proc.new { |s| s.duration }
        end

        def truncate_samples
          if @samples.length > max_samples
            @samples = @samples.sort_by(&sort_for_truncation) unless sort_for_truncation.nil?
            @samples = @samples.last(max_samples)
          end
        end

        def visit_segment(*)
          # no-op
        end
      end
    end
  end
end
