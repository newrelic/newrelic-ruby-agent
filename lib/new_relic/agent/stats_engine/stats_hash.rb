# A Hash-descended class for storing metric data in the NewRelic Agent.
#
# Keys are NewRelic::MetricSpec objects.
# Values are NewRelic::Stats objects.
#
# Missing keys will be automatically created as empty NewRelic::Stats instances,
# so use has_key? explicitly to check for key existence.
#
# This class makes no provisions for safe usage from multiple threads, such
# measures should be externally provided.
module NewRelic
  module Agent
    class StatsHash < ::Hash
      def initialize
        super { |hash, key| hash[key] = NewRelic::Stats.new }
      end

      def record(metric_name_or_spec, value=nil, options={})
        if metric_name_or_spec.is_a?(NewRelic::MetricSpec)
          spec = metric_name_or_spec
        else
          scope = options[:scope]
          spec = NewRelic::MetricSpec.new(metric_name_or_spec, scope)
        end

        stats = self[spec]
        if block_given?
          yield stats
        else
          if options[:exclusive]
            stats.record_data_point(value, options[:exclusive])
          else
            stats.record_data_point(value)
          end
        end
      end

      def merge!(other)
        other.each do |key,val|
          if self.has_key?(key)
            self[key].merge!(val)
          else
            self[key] = val
          end
        end
      end
    end
  end
end