module NewRelic
  module Agent
    module CrossProcessMonitoring

      module_function

      def insert_response_header(request, response)
        if Agent.config[:'cross_process.enabled'] &&
            NewRelic::Agent.instance.cross_process_id && (id = id_from_request(request))

          content_length = -1
          timings = NewRelic::Agent::BrowserMonitoring.timings

          # FIXME the transaction name might not be properly encoded.  use a json generator
          payload = %[["#{NewRelic::Agent.instance.cross_process_id}","#{timings.transaction_name}",#{timings.queue_time_in_millis},#{timings.app_time_in_millis},#{content_length}] ]
          payload = obfuscate_with_key(payload, NewRelic::Agent.instance.cross_process_encoding_bytes)

          response['X-NewRelic-App-Data'] = payload
          #FIXME generate ClientApplication metric.  id must be decoded first
          # String metricName = MessageFormat.format("ClientApplication/{0}/all", id);
        end
      end

      def obfuscate_with_key(text, key_bytes)
        obfuscated = ""
        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ key_bytes[index % key_bytes.length].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

      def id_from_request(request)
        %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}.each do |header|
          return request.env[header] if request.env.has_key?(header)
        end
        nil
      end
    end
  end
end
