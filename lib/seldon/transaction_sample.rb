module Seldon
  class TransactionSample
    class Segment
      attr_reader :entry_timestamp
      attr_reader :exit_timestamp
      attr_reader :parent_segment
      attr_reader :metric_name
      
      def initialize(timestamp, metric_name)
        @entry_timestamp = timestamp
        @metric_name = metric_name
        @called_segments = []
      end
      
      def end_trace(timestamp)
        @exit_timestamp = timestamp
      end
      
      def add_called_segment(s)
        @called_segments << s
        s.parent_segment = self
      end
      
      def to_debug_str(depth)
        tab = "" 
        depth.times {tab << "  "}
        
        s = tab.clone
        s << ">> #{metric_name}: #{@entry_timestamp}\n"
        called_segments.each do |cs|
          s << cs.to_debug_str(depth + 1)
        end
        s << tab
        s << "<< #{metric_name}: #{@exit_timestamp}\n"
        s
      end
      
      def called_segments
        @called_segments.clone
      end
      
      def freeze
        @called_segments.each do |s|
          s.freeze
        end
        super
      end
      
      protected
        def parent_segment=(s)
          @parent_segment = s
        end
    end

    attr_accessor :start_time
    attr_reader :root_segment
    
    def begin_building()
      @start_time = Time.now
      @root_segment = create_segment 0.0, "ROOT"
    end

    def create_segment (relative_timestamp, metric_name)
      raise TypeError.new("Frozen Transaction Sample") if frozen?
      Seldon::TransactionSample::Segment.new(relative_timestamp, metric_name)    
    end
    
    def freeze
      @root_segment.freeze
      super
    end
    
    def to_s
      "Transaction Sample collected at #{:start_time}\n " + @root_segment.to_debug_str(0)
    end
  end
  
end
