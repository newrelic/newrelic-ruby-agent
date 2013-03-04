# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# A Hash-descended class for storing metric data in the NewRelic Agent.
#
# Keys are NewRelic::MetricSpec objects.
# Values are NewRelic::Agent::Stats objects.
#
# Missing keys will be automatically created as empty NewRelic::Agent::Stats
# instances, so use has_key? explicitly to check for key existence.
#
# This class makes no provisions for safe usage from multiple threads, such
# measures should be externally provided.
module NewRelic
  module Agent
    class StatsHash < ::Hash
      def initialize
        super { |hash, key| hash[key] = NewRelic::Agent::Stats.new }
      end

      def marshal_dump
        Hash[self]
      end

      def marshal_load(hash)
        self.merge!(hash)
      end

      def ==(other)
        Hash[self] == Hash[other]
      end

      def record(metric_specs, value=nil)
        Array(metric_specs).each do |metric_spec|
          stats = self[metric_spec]
          if block_given?
            yield stats
          else
            case value
            when Numeric
              stats.record_data_point(value)
            when NewRelic::Agent::Stats
              stats.merge!(value)
            end
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
        self
      end
    end
  end
end