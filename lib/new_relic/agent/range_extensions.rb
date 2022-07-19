# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module RangeExtensions
      module_function

      def intersects?(r1, r2)
        r1.include?(r2.begin) || r2.include?(r1.begin)
      end

      # Computes the amount of overlap between range and an array of ranges.
      # For efficiency, it assumes that range intersects with each of the
      # ranges in the ranges array.
      def compute_overlap(range, ranges)
        ranges.inject(0) do |memo, other|
          next memo unless intersects?(range, other)
          lower_bound = range.begin > other.begin ? range.begin : other.begin
          upper_bound = range.end < other.end ? range.end : other.end
          memo += upper_bound - lower_bound
        end
      end
    end
  end
end
