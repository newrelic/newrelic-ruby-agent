module NewRelic
  module Agent
    module BrowserMonitoring
      def browser_instrumentation_header(options={})
        
        options = {:protocol => 'https'}.merge(options)
        
        license_key = NewRelic::Agent.instance.browser_monitoring_key
        
        return "" if license_key.nil?

        application_id = NewRelic::Agent.instance.application_id
        beacon = NewRelic::Agent.instance.beacon
        episodes_file = NewRelic::Agent.instance.episodes_file
 
        transaction_name = Thread::current[:newrelic_scope_name] || "<unknown>"
        
        # Agents are hard-coded to a particular episodes JS file. This allows for radical future change
        # to the contents of that file
        file = "\"#{options[:protocol]}://#{episodes_file}\""
        
<<-eos
<script src=#{file} type="text/javascript"></script><script type="text/javascript" charset="utf-8">NR_RUM.setContext("#{beacon}","#{license_key}","#{application_id}","#{transaction_name}")</script>
eos
      end
      
      def browser_instrumentation_footer(options={})
        
        return "" if NewRelic::Agent.instance.browser_monitoring_key.nil?
        
        frame = Thread.current[:newrelic_metric_frame]
        
        if frame && frame.start
          # HACK ALERT - there's probably a better way for us to get the queue-time
          queue_time = ((Thread.current[:queue_time] || 0).to_f * 1000.0).round
          app_time = ((Time.now - frame.start).to_f * 1000.0).round
 
<<-eos
<script type="text/javascript" charset="utf-8">NR_RUM.recordFooter(#{queue_time},#{app_time})</script>
eos
        end
      end
    end
  end
end
