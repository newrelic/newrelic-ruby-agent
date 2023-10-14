# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'

module NewRelic::Agent::Instrumentation
  module Ethon
    module Easy
      INSTRUMENTATION_NAME = 'Ethon'
      ACTION_INSTANCE_VAR = :@nr_action
      HEADERS_INSTANCE_VAR = :@nr_headers
      NOTICEABLE_ERROR_CLASS = 'Ethon::Errors::EthonError'

      # `Ethon::Easy` doesn't expose the "action name" ('GET', 'POST', etc.)
      # and Ethon's fabrication of HTTP classes uses
      # `Ethon::Easy::Http::Custom` for non-standard actions. To be able to
      # know the action name at `#perform` time, we set a new instance variable
      # on the `Ethon::Easy` instance with the base name of the fabricated
      # class, respecting the 'Custom' name where appropriate.
      def fabricate_with_tracing(_url, action_name, _options)
        fabbed = yield
        instance_variable_set(ACTION_INSTANCE_VAR, NewRelic::Agent.base_name(fabbed.class.name).upcase)
        fabbed
      end

      # `Ethon::Easy` uses `Ethon::Easy::Header` to set request headers on
      # libcurl with `#headers=`. After they are set, they aren't easy to get
      # at again except via FFI so set a new instance variable on the
      # `Ethon::Easy` instance to store them in Ruby hash format.
      def headers_equals_with_tracing(headers)
        instance_variable_set(HEADERS_INSTANCE_VAR, headers)
        yield
      end

      def perform_with_tracing(*args)
        return unless NewRelic::Agent::Tracer.state.is_execution_traced?

        NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

        wrapped_request = ::NewRelic::Agent::HTTPClients::EthonHTTPRequest.new(self)
        segment = NewRelic::Agent::Tracer.start_external_request_segment(
          library: wrapped_request.type,
          uri: wrapped_request.uri,
          procedure: wrapped_request.method
        )
        segment.add_request_headers(wrapped_request)

        callback = proc do
          if response_code == 0
            e = NewRelic::Agent::NoticeableError.new(NOTICEABLE_ERROR_CLASS, "return_code: >>#{return_code}<<")
            segment.notice_error(e)
          else
            segment.instance_variable_set(:@http_status_code, response_code)
          end

          ::NewRelic::Agent::Transaction::Segment.finish(segment)
        end

        on_complete { callback.call }

        yield
      ensure
        ::NewRelic::Agent::Transaction::Segment.finish(segment)
      end
    end
  end
end
