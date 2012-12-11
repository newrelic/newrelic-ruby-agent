module NewRelic
  module Agent
    # This class contains the configuration data for setting up RUM
    # headers and footers - acts as a cache of this data so we don't
    # need to look it up or reconfigure it every request
    class BeaconConfiguration

      # the statically generated header - generated when the beacon
      # configuration is created - does not vary per page
      attr_reader :browser_timing_header

      # the static portion of the RUM footer - this part does not vary
      # by which request is in progress
      attr_reader :browser_timing_static_footer

      # RUM footer command used for 'finish' - based on whether JSONP is
      # being used. 'nrfj' for JSONP, otherwise 'nrf2'
      attr_reader :finish_command

      # A static javascript header that is identical for every account
      # and application
      JS_HEADER = "<script type=\"text/javascript\">var NREUMQ=NREUMQ||[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);</script>"

      # Creates a new browser configuration data. Argument is a hash
      # of configuration values from the server
      def initialize
        @browser_timing_header = build_browser_timing_header
        NewRelic::Control.instance.log.debug("Browser timing header: #{@browser_timing_header.inspect}")
        @browser_timing_static_footer = build_load_file_js
        NewRelic::Control.instance.log.debug("Browser timing static footer: #{@browser_timing_static_footer.inspect}")
        if Agent.config[:'rum.jsonp']
          NewRelic::Control.instance.log.debug("Real User Monitoring is using JSONP protocol")
          @finish_command = 'nrfj'
        else
          @finish_command = 'nrf2'
        end

        if !Agent.config[:'rum.enabled']
          NewRelic::Control.instance.log.warn("Real User Monitoring is disabled for this agent. Edit your configuration to change this.")
        end
      end

      def enabled?
        Agent.config[:'rum.enabled'] && !!Agent.config[:beacon]
      end

      # returns a memoized version of the bytes in the license key for
      # obscuring transaction names in the javascript
      def license_bytes
        if @license_bytes.nil?
          @license_bytes = []
          Agent.config[:license_key].each_byte {|byte| @license_bytes << byte}
        end
        @license_bytes
      end

      # returns a snippet of text that does not change
      # per-transaction. Is empty when rum is disabled, or we are not
      # including the episodes file dynamically (i.e. the user
      # includes it themselves)
      def build_load_file_js
        js = <<-EOS
if (!NREUMQ.f) { NREUMQ.f=function() {
NREUMQ.push(["load",new Date().getTime()]);
EOS

        if Agent.config[:'rum.load_episodes_file'] &&
          Agent.config[:'rum.load_episodes_file'] != ''
          js << <<-EOS
var e=document.createElement("script");
e.type="text/javascript";
e.src=(("http:"===document.location.protocol)?"http:":"https:") + "//" +
  "#{Agent.config[:episodes_file]}";
document.body.appendChild(e);
EOS
        end

        js << <<-EOS
if(NREUMQ.a)NREUMQ.a();
};
NREUMQ.a=window.onload;window.onload=NREUMQ.f;
};
EOS
        js
      end

      # returns a copy of the static javascript header, in case people
      # are munging strings somewhere down the line
      def javascript_header
        JS_HEADER.dup
      end

      # Returns the header string, properly html-safed if needed
      def build_browser_timing_header
        return "" if !enabled?
        return "" if Agent.config[:browser_key].nil?

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
