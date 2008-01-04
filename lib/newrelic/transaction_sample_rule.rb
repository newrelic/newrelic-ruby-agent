module NewRelic
  class TransactionSampleRule
    attr_accessor :duration
    attr_accessor :max_sample_count
    attr_accessor :metric_name
    
    def initialize(metric_name, max_sample_count = 5, duration = 30.0)
      self.metric_name = metric_name
      self.max_sample_count = max_sample_count.to_i
      self.duration = duration.to_f
      
      # the rule is created in a different process
      # from where it is executed.  
      @executing = false
    end
    
    def check(metric)
      begin_executing
      
      return false if has_expired?
      if (metric_name == metric)
        @check_count += 1
        return true
      end
      
      false
    end
    
    def has_expired?
      begin_executing
      @check_count >= max_sample_count || Time.now > @expiration_time
    end
    
    def to_s
      "Rule: duration=#{duration}, max count = #{max_sample_count}, metric = #{metric_name}"
    end
    
    private
      def begin_executing
        unless @executing
          @executing = true
          @expiration_time = Time.now + duration
          @check_count = 0
        end
      end
  end
end