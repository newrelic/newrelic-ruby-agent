# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Segments
        module Server
          def set_server_transaction_name(original_name, tracer_name, attributes)
            attributes ||= NewRelic::EMPTY_HASH
            host = attributes['server.address'] || attributes['http.host']
            method = attributes['http.request.method'] || attributes['http.method']
            path = attributes['url.path'] || attributes['http.target']

            if [host, method, path].any?(&:nil?)
              original_name
            else
              "Controller/#{tracer_name}/#{host}/#{method} #{path}"
            end
          end

          def update_request_attributes(nr_item, attributes)
            return unless nr_item.is_a?(Transaction)

            request_attributes = nr_item.instance_variable_get(:@request_attributes)

            return unless request_attributes.is_a?(NewRelic::Agent::Transaction::RequestAttributes)

            attributes ||= NewRelic::EMPTY_HASH
            host = attributes['server.address'] || attributes['http.host']
            method = attributes['http.request.method'] || attributes['http.method']
            path = attributes['url.path'] || attributes['http.target']
            user_agent = attributes['user_agent.original'] || attributes['http.user_agent']

            request_attributes.instance_variable_set(:@host, host) if host
            request_attributes.instance_variable_set(:@request_method, method) if method
            request_attributes.instance_variable_set(:@request_path, path) if path
            request_attributes.instance_variable_set(:@user_agent, user_agent) if user_agent
          end
        end
      end
    end
  end
end
