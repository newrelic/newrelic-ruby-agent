# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/transaction_sample'
require 'new_relic/transaction_sample/segment'
module NewRelic
  class TransactionSample
    class SummarySegment < Segment
      def initialize(segment)
        super segment.entry_timestamp, segment.metric_name, nil

        add_segments segment.called_segments

        end_trace segment.exit_timestamp
      end

      def add_segments(segments)
        segments.collect do |segment|
          SummarySegment.new(segment)
        end.each {|segment| add_called_segment(segment)}
      end
    end
  end
end
