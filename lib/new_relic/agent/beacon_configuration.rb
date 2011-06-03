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

      JS_HEADER = "<script type=\"text/javascript\">var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);</script>"

      def initialize(connect_data)
        @browser_monitoring_key = connect_data['browser_key']
        @application_id = connect_data['application_id']
        @beacon = connect_data['beacon']
        @rum_enabled = connect_data['rum.enabled']
        @rum_enabled = true if @rum_enabled.nil?
        NewRelic::Control.instance.log.warn("Real User Monitoring is disabled for this agent. Edit your configuration to change this.") unless @rum_enabled
        @browser_timing_header = build_browser_timing_header
        NewRelic::Control.instance.log.debug("Browser timing header: #{@browser_timing_header.inspect}")
        @browser_timing_static_footer = build_load_file_js(connect_data)
        NewRelic::Control.instance.log.debug("Browser timing static footer: #{@browser_timing_static_footer.inspect}")
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
        
        s = 
<<-eos
NREUMQ.f = function() {
NREUMQ.push(["load",new Date().getTime()]);
var e=document.createElement(\"script\");
e.type=\"text/javascript\";e.async=true;e.src=\"#{episodes_url}\";
document.body.appendChild(e);  
if (NREUMQ.a) NREUMQ.a();
};
NREUMQ.a=window.onload;window.onload=NREUMQ.f;          
eos
        s
      end

      def javascript_header
        JS_HEADER.dup
      end

      def build_browser_timing_header
        return "" if !@rum_enabled
        return "" if @browser_monitoring_key.nil?
        
        value = javascript_header
        if value.respond_to?(:html_safe)
          value.html_safe
        else
          value
        end
      end
    end
  end
end


