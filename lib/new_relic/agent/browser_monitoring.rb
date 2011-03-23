require 'base64'

module NewRelic
  module Agent
    module BrowserMonitoring
      
      def browser_timing_short_header
        return "" if browser_monitoring_key.nil?
        "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()])</script>"
      end
      
      def browser_timing_header(protocol=nil)

        return "" if browser_monitoring_key.nil?

        if protocol
          if !protocol.eql?("http") && !protocol.eql?("https")
            protocol = "\"https:"
          else
            protocol = "\"#{protocol}:"
          end
        else
          protocol = "((\"http:\"===d.location.protocol)?\"http:\":\"https:\")+\""
        end

        load_js = "(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=#{protocol}//#{episodes_file}\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()"
        "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);#{load_js}</script>"
      end
      
      def browser_timing_footer
        
        return "" if browser_monitoring_key.nil?
        
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