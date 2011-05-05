require 'base64'
require 'new_relic/agent/beacon_configuration'
module NewRelic
  module Agent
    module BrowserMonitoring

      def browser_timing_header
        #return no header if outside a transaction, if already instrumented with a header, or if tracing is disabled
        return "" if Thread.current[:newrelic_most_recent_transaction].nil? || Thread.current[:newrelic_most_recent_transaction][:rum_header_added]
        return "" if NewRelic::Agent.instance.beacon_configuration.nil?
        return "" if !NewRelic::Agent.is_transaction_traced? || !NewRelic::Agent.is_execution_traced?
        
        Thread.current[:newrelic_most_recent_transaction][:rum_header_added] = true
        NewRelic::Agent.instance.beacon_configuration.browser_timing_header
      end

      def browser_timing_footer
        #return no footer if already instrumented or if the footer is requested before/without a header
        return "" if Thread.current[:newrelic_most_recent_transaction].nil? || Thread.current[:newrelic_most_recent_transaction][:rum_footer_added] || !Thread.current[:newrelic_most_recent_transaction][:rum_header_added]
        config = NewRelic::Agent.instance.beacon_configuration
        return "" if config.nil? || !config.rum_enabled
       
        license_key = config.browser_monitoring_key
        return "" if license_key.nil?

        return "" if !NewRelic::Agent.is_transaction_traced? || !NewRelic::Agent.is_execution_traced?
          
        application_id = config.application_id
        beacon = config.beacon

        transaction_name = Thread.current[:newrelic_most_recent_transaction][:scope_name] || "<unknown>"
        start_time = Thread.current[:newrelic_start_time]
        queue_time = (Thread.current[:newrelic_queue_time].to_f * 1000.0).round

        value = ''
        if start_time

          obf = obfuscate(transaction_name)
          app_time = ((Time.now - start_time).to_f * 1000.0).round

          queue_time = 0.0 if queue_time < 0
          app_time = 0.0 if app_time < 0

          value = <<-eos
<script type="text/javascript" charset="utf-8">NREUMQ.push(["nrf2","#{beacon}","#{license_key}",#{application_id},"#{obf}",#{queue_time},#{app_time}])</script>
eos
        end
        Thread.current[:newrelic_most_recent_transaction][:rum_footer_added] = true
        if value.respond_to?(:html_safe)
          value.html_safe
        else
          value
        end
      end

      private

      def obfuscate(text)
        obfuscated = ""
        key_bytes = NewRelic::Agent.instance.beacon_configuration.license_bytes
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % 13].to_i))
          index+=1
        }

        [obfuscated].pack("m0").chomp
      end
    end
  end
end
