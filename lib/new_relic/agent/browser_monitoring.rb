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
<script type="text/javascript" charset="utf-8">NREUMQ.push(["nrfinish2","#{beacon}","#{license_key}","#{application_id}","#{obf}","#{queue_time}","#{app_time}"])</script>
eos
        end
      end
      
      private

      def obfuscate(text)
        obfuscated = ""
        keyIndex = -1
        key = NewRelic::Control.instance.license_key
        text.bytes.each { |byte|
          keyIndex = keyIndex + 1
          keyIndex = 0 if keyIndex >= 13
          obfuscated.concat(byte ^ key[keyIndex])
        }
        Base64.encode64(obfuscated).gsub(/\n/, '')
      end
      
#      BASE64 = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", 
#                "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
#                "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "/"]
#      HI6 = 0b11111100
#      LO2 = 0b00000011
#      HI4 = 0b11110000
#      LO4 = 0b00001111
#      HI2 = 0b11000000
#      LO6 = 0b00111111
#      
#      # Encodes a string into base64
#      def encode(text)
#        result = ""
#        num = 0
#        b1 = 0
#        b2 = 0
#        b3 = 0
#        text.bytes.each { |byte|
#          #process in groups of 3 bytes
#          case num
#            when 0
#              b1 = byte
#              num = num + 1
#            when 1
#              b2 = byte
#              num = num + 1
#            when 2
#              b3 = byte
#              num = 0
#              result = result + chunk(b1, b2, b3, 0)
#              b1 = 0
#              b2 = 0
#              b3 = 0
#          end
#        }
#        if num > 0
#          result = result + chunk(b1, b2, b3, 3 - num)
#        end
#        result
#      end
#      
#      def chunk(b1, b2, b3, pad)
#        result = ""
#        c1 = (HI6 & b1) >> 2
#        c2 = ((LO2 & b1) << 4) | ((HI4 & b2) >> 4)
#        c3 = ((HI4 & b2) << 2) | ((HI2 & b3) >> 6)
#        c4 = LO6 & b3
#        
#        result = result + BASE64[c1] + BASE64[c2]
#        if pad == 2
#          result = result + "=="
#        else
#          result = result + BASE64[c3]
#          if pad == 1
#            result = result + "="
#          else
#            result = result + BASE64[c4]
#          end
#        end
#        result
#      end
      
    end
  end
end
