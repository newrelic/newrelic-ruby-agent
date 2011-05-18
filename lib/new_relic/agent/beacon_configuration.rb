module NewRelic
  module Agent
    class BeaconConfiguration
      attr_reader :browser_timing_header
      attr_reader :browser_timing_static_footer
      attr_reader :application_id
      attr_reader :browser_monitoring_key
      attr_reader :beacon
      attr_reader :rum_enabled
      attr_reader :license_bytes

      JS_HEADER = "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);</script>"

      def initialize(connect_data)
        @browser_monitoring_key = connect_data['browser_key']
        @application_id = connect_data['application_id']
        @beacon = connect_data['beacon']
        @rum_enabled = connect_data['rum.enabled']
        @rum_enabled = true if @rum_enabled.nil?
        @browser_timing_header = build_browser_timing_header
        @browser_timing_static_footer = build_load_file_js(connect_data) 
      end

      def license_bytes
        if @license_bytes.nil?
          @license_bytes = []
          NewRelic::Control.instance.license_key.each_byte {|byte| @license_bytes << byte}
        end
        @license_bytes
      end

      def build_load_file_js(connect_data)
        return "" unless connect_data.fetch('rum.load_episodes_file', true)

        episodes_url = connect_data.fetch('episodes_url', '')
        "(function(){var d=document;var e=d.createElement(\"script\");e.async=true;e.src=\"#{episodes_url}\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})();"
      end

      def build_browser_timing_header
        return "" if !@rum_enabled
        return "" if @browser_monitoring_key.nil?
        
        # TODO: Justin - can you review this? Given that this is a constant string is this work necessary?
        value = JS_HEADER
        if value.respond_to?(:html_safe)
          value.html_safe
        else
          value
        end
      end
    end
  end
end


