# encoding: utf-8
# frozen_string_literal: true
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../helper'

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Server
          include NewRelic::Agent::Instrumentation::GRPC::Helper
          include NewRelic::Agent::Instrumentation::ControllerInstrumentation

          INSTANCE_VAR_HOST = :@host_nr
          INSTANCE_VAR_PORT = :@port_nr
          INSTANCE_VAR_METHOD = :@method_nr

          def handle_with_tracing(active_call, mth, _inter_ctx)
            return yield unless trace_with_newrelic?
            metadata = metadata_for_call(active_call)
            result_code = 0
            # rescue => put handling for exceptions to get at the non-zero code
            # in the ensure block
            # response - how do we add the response code?
            # ability to turn off the server's status code?
            perform_action_with_newrelic_trace(server_options(metadata)) do
              process_distributed_tracing_headers(metadata)
              yield
            end
          end

          def add_http2_port_with_tracing(*args)
            set_host_and_port_on_server_instance(args.first)
            yield
          end

          def run_with_tracing(*args)
            set_host_and_port_and_method_info_on_desc
            yield
          end

          private

          def metadata_for_call(active_call)
            return NewRelic::EMPTY_HASH unless active_call && active_call.metadata

            active_call.metadata
          end

          def process_distributed_tracing_headers(metadata)
            return unless metadata && !metadata.empty?

            ::NewRelic::Agent::DistributedTracing::accept_distributed_trace_headers(metadata, 'Other')
          end

          def host_and_port_from_host_string(host_string)
            return unless host_string

            info = host_string.split(':').freeze
            return unless info.size == 2

            info
          end

          def set_host_and_port_on_server_instance(host_string)
            info = host_and_port_from_host_string(host_string)
            return unless info

            instance_variable_set(INSTANCE_VAR_HOST, info.first)
            instance_variable_set(INSTANCE_VAR_PORT, info.last)
          end

          def set_host_and_port_and_method_info_on_desc
            rpc_descs.each do |method, desc|
              desc.instance_variable_set(INSTANCE_VAR_HOST, instance_variable_get(INSTANCE_VAR_HOST))
              desc.instance_variable_set(INSTANCE_VAR_PORT, instance_variable_get(INSTANCE_VAR_PORT))
              desc.instance_variable_set(INSTANCE_VAR_METHOD, cleaned_method(method))
            end
          end

          def server_options(headers)
            host = instance_variable_get(INSTANCE_VAR_HOST)
            port = instance_variable_get(INSTANCE_VAR_PORT)
            method = instance_variable_get(INSTANCE_VAR_METHOD)
            {
              request: {
                headers: headers,
                uri: "grpc://#{host}:#{port}/#{method}",
                method: method
              },
              category: :web,
              transaction_name: "Controller/#{method}"
            }
          end

          def trace_with_newrelic?
            do_trace = instance_variable_get(:@trace_with_newrelic)
            return do_trace unless do_trace.nil? # check for nil, not falsey

            host = instance_variable_get(INSTANCE_VAR_HOST)
            return true unless host

            do_trace = !host_denylisted?(host)
            instance_variable_set(:@trace_with_newrelic, do_trace)

            do_trace
          end
        end
      end
    end
  end
end
