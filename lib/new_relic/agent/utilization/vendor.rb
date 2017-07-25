# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'

module NewRelic
  module Agent
    module Utilization
      class Vendor
        class << self
          def provider_name provider_name = nil
            provider_name ? @provider_name = provider_name.freeze : @provider_name
          end

          def endpoint endpoint = nil
            endpoint ? @endpoint = URI(endpoint) : @endpoint
          end

          def headers headers = nil
            headers ? @headers = headers.freeze : @headers
          end

          def keys keys = nil
            keys ? @keys = keys.freeze : @keys
          end
        end

        def initialize
          @metadata = {}
        end

        [:provider_name, :endpoint, :headers, :keys].each do |method_name|
          define_method(method_name) { self.class.send(method_name) }
        end

        def process
          response = request_metadata
          if response.code == '200'
            assign_keys response.body
          end
        rescue => e
          NewRelic::Agent.logger.error "Unexpected error obtaining utilization data for #{provider_name}", e
        end

        def to_collector_hash
          {
            provider_name => @metadata
          }
        end

        private

        def request_metadata
          response = nil
          Net::HTTP.start endpoint.host, endpoint.port do |http|
            req = Net::HTTP::Get.new endpoint, headers
            response = http.request req
          end
          response
        end

        def assign_keys response
          parsed_response = JSON.parse response
          keys.each do |key|
            @metadata[key] = parsed_response[key]
          end
        end

        def record_supportability_metric
          Agent.increment_metric "Supportability/utilization/#{provider_name}/error"
        end
      end
    end
  end
end
