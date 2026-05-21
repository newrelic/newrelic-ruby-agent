# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class HttpClientTranslator < BaseTranslator
        class << self
          def mappings_hash
            AttributeMappings::HTTP_CLIENT_MAPPINGS
          end

          def add_specialized_attributes(result: {}, name: nil, attributes: nil, instrumentation_scope: nil)
            uri = build_uri(attributes)
            result[:for_segment_api][:uri] = uri if uri

            result
          end

          def build_uri(attributes)
            scheme = attributes['url.scheme'] || attributes['http.scheme']
            host = attributes['server.address'] || attributes['net.peer.name']
            port = attributes['server.port'] || attributes['net.peer.port']
            path = attributes['url.path'] || attributes['http.target'] || NewRelic::SLASH

            if [scheme, host, port, path].any?(&:nil?)
              attributes['url.full'] || attributes['http.url']
            else
              "#{scheme}://#{host}:#{port}#{path}"
            end
          end
        end
      end
    end
  end
end
