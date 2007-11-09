module Seldon
  module MetricParser
    # FIXME revisit this design - centralizing this stuff decouples metric name
    # knowledge from the metrics themselves.
    SEPARATOR = '/'
    
    @segments = nil

    def is_web_service?
      segments[0] == "WebService" && segments[1] != 'Soap' && segments[1] != 'Xml Rpc'
    end
    
    def is_controller?
      segments[0] == "Controller"  && segments.length > 1
    end
    
    def is_url?
      segments[0] == "URL"
    end
    
    def is_render?
      segments.last == "Rendering"
    end
    
    def is_database?
      segments[0] == "ActiveRecord"
    end
    
    def is_front_end?
      is_url?
    end
    
    def is_database_read?
      is_database? && segments[-1] == "find" && segments.length > 2
    end
    
    def is_database_write?
      is_database? && segments[-1] == "save" && segments.length > 2
    end
    
    # TODO fix me
    def short_name
      segments[1..-1].join(SEPARATOR)
    end
    
    def category
      segments[0]
    end
    
    def parent(segment_count)
      return name if segment_count >= segments.length
      segments[0..segment_count].join(SEPARATOR)
    end
    
    def segments
      @segments ||= name.split(SEPARATOR).freeze
      @segments
    end
  end
end