# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Segments
        module HttpExternal
          def create_uri(attributes)
            scheme = attributes['url.scheme'] || attributes['http.scheme']
            host = attributes['server.address'] || attributes['net.peer.name']
            port = attributes['server.port'] || attributes['net.peer.port']
            path = attributes['url.path'] || attributes['http.target'] || NewRelic::SLASH

            # if we don't have all the pieces we need to build a full URI,
            # fall back to the full URL representations;
            # though these don't usually have a port
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
