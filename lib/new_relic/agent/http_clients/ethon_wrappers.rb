# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'
require_relative 'abstract'

module NewRelic
  module Agent
    module HTTPClients
      # NOTE: There isn't an `EthonHTTPResponse` class. Typically HTTP
      #       instrumentation response wrapper class instances are passed to
      #       `ExternalRequestSegment#process_response_headers` in order to
      #         - set the HTTP status code on the segment
      #         - to process CAT headers
      #       Given that:
      #         - `Ethon::Easy` doesn't create a response object and only uses
      #           instance methods for interacting with the response
      #         - We do not plan to support CAT for new instrumentation
      #       The decision was made to forego a response wrapper class for Ethon
      #       and simply set the HTTP status code on the segment directly

      class EthonHTTPRequest < AbstractRequest
        attr_reader :uri

        DEFAULT_ACTION = 'unknownaction'
        DEFAULT_HOST = 'unknownhost'
        ETHON = 'Ethon'
        LHOST = 'host'.freeze
        UHOST = 'Host'.freeze

        def initialize(easy)
          @easy = easy
          @uri = uri_from_easy
        end

        def type
          ETHON
        end

        def host_from_header
          self[LHOST] || self[UHOST]
        end

        def uri_from_easy
          # anticipate `Ethon::Easy#url` being `example.com` without a protocol
          # defined and use an 'http' protocol prefix for `URI.parse` to work
          # with the URL as desired
          url_str = @easy.url.match?(':') ? @easy.url : "http://#{@easy.url}"
          begin
            URI.parse(url_str)
          rescue URI::InvalidURIError => e
            NewRelic::Agent.logger.debug("Failed to parse URI '#{url_str}': #{e.class} - #{e.message}")
            URI.parse(NewRelic::EMPTY_STR)
          end
        end

        def host
          host_from_header || uri.host&.downcase || DEFAULT_HOST
        end

        def method
          return DEFAULT_ACTION unless @easy.instance_variable_defined?(action_instance_var)

          @easy.instance_variable_get(action_instance_var)
        end

        def action_instance_var
          NewRelic::Agent::Instrumentation::Ethon::Easy::ACTION_INSTANCE_VAR
        end

        def headers_instance_var
          NewRelic::Agent::Instrumentation::Ethon::Easy::HEADERS_INSTANCE_VAR
        end

        def [](key)
          headers[key]
        end

        def []=(key, value)
          headers[key] = value
          @easy.headers = headers
        end

        def headers
          @headers ||= if @easy.instance_variable_defined?(headers_instance_var)
            @easy.instance_variable_get(headers_instance_var)
          else
            {}
          end
        end
      end
    end
  end
end
