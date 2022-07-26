# encoding: utf-8
# frozen_string_literal: true
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'request_wrapper'
require_relative '../helper'

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Client
          include NewRelic::Agent::Instrumentation::GRPC::Helper

          def issue_request_with_tracing(method, requests, marshal, unmarshal,
            deadline:, return_op:, parent:, credentials:, metadata:)
            return yield unless trace_with_newrelic?

            segment = request_segment(method)
            request_wrapper = NewRelic::Agent::Instrumentation::GRPC::Client::RequestWrapper.new(@host)
            segment.add_request_headers(request_wrapper)
            metadata.merge!(metadata, request_wrapper.instance_variable_get(:@newrelic_metadata))

            NewRelic::Agent.disable_all_tracing do
              NewRelic::Agent::Tracer.capture_segment_error(segment) do
                yield
              end
            end
          ensure
            segment.finish if segment
          end

          private

          def request_segment(method)
            cleaned = cleaned_method(method)
            NewRelic::Agent::Tracer.start_external_request_segment(
              library: 'gRPC',
              uri: method_uri(cleaned),
              procedure: cleaned
            )
          end

          def method_uri(method)
            return unless @host && method

            "grpc://#{@host}/#{method}"
          end

          def trace_with_newrelic?(host = nil)
            return false if self.class.name.eql?('GRPC::InterceptorRegistry')

            do_trace = instance_variable_get(:@trace_with_newrelic)
            return do_trace unless do_trace.nil? # check for nil, not falsey

            host ||= @host
            return false unless host && !host_denylisted?(host)

            true
          end
        end
      end
    end
  end
end
