require 'base64'

module NewRelic
  module Agent
    module BrowserMonitoring
      def browser_instrumentation_header(options={})
        
        return "" if NewRelic::Agent.instance.browser_monitoring_key.nil?
        
        episodes_file = "//" + NewRelic::Agent.instance.episodes_file
        
        if options[:manual_js_load]
          load_js = ""
        else
          load_js = "(function(){var e=document.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=document.location.protocol+\"#{episodes_file}\";var s=document.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})();"
        end
      
        "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);#{load_js}</script>"
      end
      
      def browser_instrumentation_footer(options={})
        
        license_key = NewRelic::Agent.instance.browser_monitoring_key
        
        return "" if license_key.nil?

        application_id = NewRelic::Agent.instance.application_id
        beacon = NewRelic::Agent.instance.beacon
        transaction_name = Thread::current[:newrelic_scope_name] || "<unknown>"
        obf = obfuscate(transaction_name)
        
        frame = Thread.current[:newrelic_metric_frame]
        
        if frame && frame.start
          # HACK ALERT - there's probably a better way for us to get the queue-time
          queue_time = ((Thread.current[:queue_time] || 0).to_f * 1000.0).round
          app_time = ((Time.now - frame.start).to_f * 1000.0).round
 
<<-eos
<script type="text/javascript" charset="utf-8">NREUMQ.push(["nrf2","#{beacon}","#{license_key}",#{application_id},"#{obf}",#{queue_time},#{app_time}])</script>
eos
        end
      end
      
      private

      def obfuscate(text)
        obfuscated = ""
        
        key = NewRelic::Control.instance.license_key
        
        text.bytes.each_with_index do |byte, i|
          obfuscated.concat((byte ^ key[i % 13]))
        end
        
        [obfuscated].pack("m0").chomp
      end
    end
  end
end
