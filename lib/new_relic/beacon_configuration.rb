module NewRelic
  module Agent
    class BeaconConfiguration
    
      attr_reader :browser_timing_header
      attr_reader :application_id
      attr_reader :browser_monitoring_key
      attr_reader :beacon
      
      def initialize(connect_data)
        @browser_monitoring_key = connect_data['browser_key']
        @application_id = connect_data['application_id']
        @beacon = connect_data['beacon']
        
        @browser_timing_header = build_browser_timing_header(connect_data)
      end
    end
    
    def build_browser_timing_header(connect_data)
      return "" if @browser_monitoring_key.nil?
      
      episodes_url = connect_data['episodes_url']
      load_episodes_file = connect_data['rum.load_episodes_file']
      load_episodes_file = true if load_episodes_file.nil?
  
      load_js = load_episodes_file ? "(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"#{episodes_url}\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()" : ""
          
      "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);#{load_js}</script>"
    end
  end
end