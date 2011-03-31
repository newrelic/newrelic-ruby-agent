require 'base64'

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
    
      def build_browser_timing_header(connect_data)
        return "" if @browser_monitoring_key.nil?
        
        episodes_url = connect_data['episodes_url']
        load_episodes_file = connect_data['rum.load_episodes_file']
        load_episodes_file = true if load_episodes_file.nil?
    
        load_js = load_episodes_file ? "(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"#{episodes_url}\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()" : ""
            
        "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);#{load_js}</script>"
      end
    end

    module BrowserMonitoring
            
      def browser_timing_header        
        return "" if NewRelic::Agent.instance.beacon_configuration.nil?
        NewRelic::Agent.instance.beacon_configuration.browser_timing_header
      end
      
      def browser_timing_footer
        config = NewRelic::Agent.instance.beacon_configuration
        return "" if config.nil?
        license_key = config.browser_monitoring_key
        
        return "" if license_key.nil?

        application_id = config.application_id
        beacon = config.beacon
        
        transaction_name = Thread::current[:newrelic_scope_name] || "<unknown>"
        frame = Thread.current[:newrelic_metric_frame]
        
        if frame && frame.start
          obf = obfuscate(transaction_name)
          
          # HACK ALERT - there's probably a better way for us to get the queue-time
          queue_time = ((Thread.current[:queue_time] || 0).to_f * 1000.0).round
          app_time = ((Time.now - frame.start).to_f * 1000.0).round
          
          queue_time = 0 if queue_time < 0
          app_time = 0 if app_time < 0
 
<<-eos
<script type="text/javascript" charset="utf-8">NREUMQ.push(["nrf2","#{beacon}","#{license_key}",#{application_id},"#{obf}",#{queue_time},#{app_time}])</script>
eos
        else
          ""
        end
      end
      
      private

      def obfuscate(text)
        obfuscated = ""
        @@license_bytes ||= NewRelic::Control.instance.license_key.bytes.to_a
        
        text.bytes.each_with_index do |byte, i|
          obfuscated.concat((byte ^ @@license_bytes[i % 13]))
        end
        
        [obfuscated].pack("m0").chomp
      end
    end
  end
end
