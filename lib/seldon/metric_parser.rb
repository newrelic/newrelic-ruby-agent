module Seldon
  module MetricParser
    SEPARATOR = '/'
    
    @segments = nil

    def is_web_service?
      segments[0] == "WebService"
    end
    
    def is_controller?
      segments[0] == "Controller"
    end
    
    def is_url?
      segments[0] == "URL"
    end
    
    def is_render?
      segments[0] == "Render"
    end
    
    def is_database?
      segments[0] == "ActiveRecord"
    end
    
    def is_front_end?
      is_url?
    end
    
    def is_database_read?
      is_database? && segments[-1] == "find"
    end
    
    def is_database_write?
      is_database? && segments[-1] == "save"
    end
    
    # TODO fix me
    def short_name
      # FIXME Hack
      return "Rendering" if is_render?
        
      sn = ""
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
      @segments = name.split(SEPARATOR).freeze unless @segments
      @segments
    end
  end
end