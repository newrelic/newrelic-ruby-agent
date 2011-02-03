module NewRelic
  module Agent
    module BrowserMonitoring
      def browser_instrumentation_header(options={})
        
        license_key = NewRelic::Agent.instance.browser_monitoring_key
        
        return "" if license_key.nil?

        application_id = NewRelic::Agent.instance.application_id
        beacon = NewRelic::Agent.instance.beacon
        episodes_file_path = NewRelic::Agent.instance.episodes_file_path
        transaction_name = Thread::current[:newrelic_scope_name] 
        
        http_part = ((episodes_file_path == "localhost:3000/javascripts") ? "http:" : "https:")
        file = "\"#{http_part}//#{episodes_file_path}/episodes_1.js\""
        
<<-eos
<script src=#{file} type="text/javascript"></script><script type="text/javascript" charset="utf-8">EPISODES.setContext("#{beacon}","#{license_key}","#{application_id}","#{transaction_name}")</script>
eos
      end
      
      def browser_instrumentation_footer(options={})
        
        return "" if NewRelic::Agent.instance.browser_monitoring_key.nil?
        
        #this is a total hack
        queue_begin_time = (Thread.current[:started_on].to_f * 1000).round
        frame = Thread.current[:newrelic_metric_frame]

        if frame
          queue_end_time = (frame.start.to_f * 1000).round
        else
          #this is a total hack
          queue_end_time = begin_time + 250
        end
        
        queue_time = queue_end_time - queue_begin_time
      
        app_begin_time = queue_end_time
        app_end_time = (Time.now.to_f * 1000).round
 
<<-eos
<script type="text/javascript" charset="utf-8">EPISODES.recordFooter(#{queue_time},#{app_begin_time},#{app_end_time})</script>
eos
      end
    end
  end
end