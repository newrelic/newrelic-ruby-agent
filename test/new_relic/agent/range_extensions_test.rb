# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/range_extensions'

module NewRelic
  module Agent
    class RangeExtensionsTest < Minitest::Test
      def test_intersects_truthy_when_overlapping
        assert RangeExtensions.intersects?((1..3), (3..5))
      end

      def test_intersects_false_when_disjoint
        refute RangeExtensions.intersects?((1...3), (3..5))
      end

      def test_compute_overlap
        result = RangeExtensions.compute_overlap(0..10, [-4..2, 6..7, 9..15])
        assert_equal 4, result
      end

      def test_compute_overlap_disjoint
        result = RangeExtensions.compute_overlap(20..30, [2..4, 6..7, 9..15])
        assert_equal 0, result
      end

      def test_compute_overlap_intersecting
        result = RangeExtensions.compute_overlap(0..10, [0..5, 5..8, 8..10])
        assert_equal 10, result
      end
    end
  end
end
