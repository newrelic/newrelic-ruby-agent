# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/range_extensions'

module NewRelic
  module Agent
    class RangeExtensionsTest < Minitest::Test

      def test_intersects_truthy_when_overlapping
        assert RangeExtensions.intersects? (1..3), (3..5)
      end

      def test_intersects_false_when_disjoint
        refute RangeExtensions.intersects? (1...3), (3..5)
      end

      def test_merge_merges_intersecting_ranges
        merged = RangeExtensions.merge (1..5), (3..8)
        assert_equal (1..8), merged
      end

      def test_merge_nil_for_disjoint_ranges
        merged = RangeExtensions.merge (1...3), (3..5)
        assert_nil merged
      end

      def test_merge_or_append_merges_intersecting_ranges
        result = RangeExtensions.merge_or_append (3..8), [(1..5), (9..13)]
        assert_equal [(1..8), (9..13)], result
      end

      def test_merge_or_append_appends_disjoint_ranges
        result = RangeExtensions.merge_or_append (6..8), [(1..5), (9..13)]
        assert_equal [(1..5), (9..13), (6..8)], result
      end

      def test_compute_overlap
        result = RangeExtensions.compute_overlap 0..10, [-4..2, 6..7, 9..15]
        assert_equal 4, result
      end

      def test_compute_overlap_disjoint
        result = RangeExtensions.compute_overlap 20..30, [2..4, 6..7, 9..15]
        assert_equal 0, result
      end

      def test_compute_overlap_intersecting
        result = RangeExtensions.compute_overlap 0..10, [0..5, 5..8, 8..10]
        assert_equal 10, result
      end
    end
  end
end
