module NewRelic
  class TransactionSample
    class Segment
      attr_reader :entry_timestamp
      attr_reader :exit_timestamp
      attr_reader :parent_segment
      attr_reader :metric_name
      attr_reader :called_segments
      
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
        s << ">> #{metric_name}: #{@entry_timestamp.to_ms}\n"
        if @params
          s << "#{tab}#{tab}{\n"
          @params.each do |k,v|
            s << "#{tab}#{tab}#{k}: #{v}\n"
          end
          s << "#{tab}#{tab}}\n"
        end
        called_segments.each do |cs|
          s << cs.to_debug_str(depth + 1)
        end
        s << tab
        s << "<< #{metric_name}: #{@exit_timestamp.to_ms}\n"
        s
      end
      
      def called_segments
        @called_segments.clone
      end
      
      def freeze
        @params.freeze if @params
        @called_segments.each do |s|
          s.freeze
        end
        super
      end
      
      # return the total duration of this segment
      def duration
        @exit_timestamp - @entry_timestamp
      end
      
      # return the duration of this segment without 
      # including the time in the called segments
      def exclusive_duration
        d = duration
        @called_segments.each do |segment|
          d -= segment.duration
        end
        d
      end
      
      def []=(key, value)
        # only create a parameters field if a parameter is set; this will save
        # bandwidth etc as most segments have no parameters
        @params ||= {}
        @params[key] = value
      end
        
      def [](key)
        return nil unless @params
        @params[key]
      end
      
      def params
        return params if params
        {}
      end
      
      # call the provided block for this segment and each 
      # of the called segments
      def each_segment(&block)
        block.call self
        
        @called_segments.each do |segment|
          segment.each_segment(&block)
        end
      end
      
      protected
        def parent_segment=(s)
          @parent_segment = s
        end
    end

    attr_accessor :start_time
    attr_reader :root_segment
    attr_reader :params
    attr_reader :sample_id
    
    def begin_building()
      @start_time = Time.now
      @root_segment = create_segment 0.0, "ROOT"
      @params = {}
      
      # FIXME use a different approach for id?
      @sample_id = object_id
    end

    def create_segment (relative_timestamp, metric_name)
      raise TypeError.new("Frozen Transaction Sample") if frozen?
      NewRelic::TransactionSample::Segment.new(relative_timestamp, metric_name)    
    end
    
    def freeze
      @root_segment.freeze
      @param.freeze
      super
    end
    
    def duration
      root_segment.duration
    end
    
    def each_segment(&block)
      @root_segment.each_segment(&block)
    end
    
    def to_s
      "Transaction Sample collected at #{start_time}\n " + 
        "Path: #{params[:path]} \n" +
        @root_segment.to_debug_str(0)
    end
  end
end
