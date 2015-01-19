# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class NewRelicService
      class Marshaller
        def parsed_error(error)
          error_type    = error['error_type']
          error_message = error['message']

          exception = case error_type
          when 'NewRelic::Agent::LicenseException'
            LicenseException.new(error_message)
          when 'NewRelic::Agent::ForceRestartException'
            ForceRestartException.new(error_message)
          when 'NewRelic::Agent::ForceDisconnectException'
            ForceDisconnectException.new(error_message)
          else
            CollectorError.new("#{error['error_type']}: #{error['message']}")
          end

          exception
        end

        def prepare(data, options={})
          encoder = options[:encoder] || default_encoder
          if data.respond_to?(:to_collector_array)
            data.to_collector_array(encoder)
          elsif data.kind_of?(Array)
            data.map { |element| prepare(element, options) }
          else
            data
          end
        end

        def default_encoder
          Encoders::Identity
        end

        def self.human_readable?
          false
        end

        protected

        def return_value(data)
          if data.respond_to?(:has_key?)
            if data.has_key?('exception')
              raise parsed_error(data['exception'])
            elsif data.has_key?('return_value')
              return data['return_value']
            end
          end
          ::NewRelic::Agent.logger.debug("Unexpected response from collector: #{data}")
          nil
        end
      end
    end
  end
end
