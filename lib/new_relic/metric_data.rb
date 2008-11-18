module NewRelic
  class MetricData
    attr_accessor :metric_spec
    attr_accessor :metric_id
    attr_accessor :stats
    
    def initialize(metric_spec, stats, metric_id)
      self.metric_spec = metric_spec
      self.stats = stats
      self.metric_id = metric_id
    end
    
    def eql?(o)
     (metric_spec.eql? o.metric_spec) && (stats.eql? o.stats)
    end
    
    def hash
      metric_spec.hash + stats.hash
    end
    
    def to_s
      "#{metric_spec.name}(#{metric_spec.scope}): #{stats}" if metric_spec
      "#{metric_id}: #{stats}" if metric_spec.nil?
    end
  end
end
