# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/coerce'

module NewRelic
  class MetricData
    # nil, or a NewRelic::MetricSpec object if we have no cached ID
    attr_reader :metric_spec
    # nil or a cached integer ID for the metric from the collector.
    attr_accessor :metric_id
    # the actual statistics object
    attr_accessor :stats

    def initialize(metric_spec, stats, metric_id)
      @metric_spec = metric_spec
      self.stats = stats
      self.metric_id = metric_id
    end

    def eql?(o)
     (metric_spec.eql? o.metric_spec) && (stats.eql? o.stats)
    end

    def original_spec
      @original_spec || @metric_spec
    end

    # assigns a new metric spec, and retains the old metric spec as
    # @original_spec if it exists currently
    def metric_spec= new_spec
      @original_spec = @metric_spec if @metric_spec
      @metric_spec = new_spec
    end

    def hash
      metric_spec.hash ^ stats.hash
    end

    # Serialize with all attributes, but if the metric id is not nil, then don't send the metric spec
    def to_json(*a)
       %Q[{"metric_spec":#{metric_id ? 'null' : metric_spec.to_json},"stats":{"total_exclusive_time":#{stats.total_exclusive_time},"min_call_time":#{stats.min_call_time},"call_count":#{stats.call_count},"sum_of_squares":#{stats.sum_of_squares},"total_call_time":#{stats.total_call_time},"max_call_time":#{stats.max_call_time}},"metric_id":#{metric_id ? metric_id : 'null'}}]
    end

    def to_s
      if metric_spec
        "#{metric_spec.name}(#{metric_spec.scope}): #{stats}"
      else
        "#{metric_id}: #{stats}"
      end
    end

    def inspect
      "#<MetricData metric_spec:#{metric_spec.inspect}, stats:#{stats.inspect}, metric_id:#{metric_id.inspect}>"
    end

    include NewRelic::Coerce

    def to_collector_array(encoder=nil)
      stat_key = metric_id || { 'name' => metric_spec.name, 'scope' => metric_spec.scope }
      [ stat_key,
        [
          int(stats.call_count, stat_key),
          float(stats.total_call_time, stat_key),
          float(stats.total_exclusive_time, stat_key),
          float(stats.min_call_time, stat_key),
          float(stats.max_call_time, stat_key),
          float(stats.sum_of_squares, stat_key)
        ]
      ]
    end
  end
end
