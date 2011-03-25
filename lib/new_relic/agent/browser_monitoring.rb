require 'base64'

module NewRelic
  module Agent
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
    
    def autoinstrument_source(source)
      if source =~ /(.*<html>)(.*)(<body)(.*)(<\/body>.*<\/html>.*)/mi
        newrelic_header = "<%= NewRelic::Agent.browser_timing_header %>"
        newrelic_footer = "<%= NewRelic::Agent.browser_timing_footer %>"

        source = $1
        after_html = $2
          
        body_tag = $3
        body = $4
        close = $5
          
        if $2 =~ /(.*)(<head>)(.*)/mi
          source << $1 << $2 << newrelic_header << $3
        else
          source << newrelic_header << after_html          
        end
          
        source << body_tag << body << newrelic_footer << close
      end
      source
    end
  end
end
