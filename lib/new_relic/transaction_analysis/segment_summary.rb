module NewRelic
  module TransactionAnalysis
    # summarizes performance data for all calls to segments
    # with the same metric_name
    class SegmentSummary
      attr_accessor :metric_name, :total_time, :exclusive_time, :call_count
      def initialize(metric_name, sample)
        @metric_name = metric_name
        @total_time, @exclusive_time, @call_count = 0,0,0
        @sample = sample
      end

      def <<(segment)
        if metric_name != segment.metric_name
          raise ArgumentError, "Metric Name Mismatch: #{segment.metric_name} != #{metric_name}"
        end

        @total_time += segment.duration
        @exclusive_time += segment.exclusive_duration
        @call_count += 1
      end

      def average_time
        @total_time / @call_count
      end

      def average_exclusive_time
        @exclusive_time / @call_count
      end

      def exclusive_time_percentage
        return 0 unless @exclusive_time && @sample.duration && @sample.duration > 0
        @exclusive_time / @sample.duration
      end

      def total_time_percentage
        return 0 unless @total_time && @sample.duration && @sample.duration > 0
        @total_time / @sample.duration
      end

      def ui_name
        return @metric_name if @metric_name == 'Remainder'
        NewRelic::MetricParser::MetricParser.parse(@metric_name).developer_name
      end
    end
  end
end
