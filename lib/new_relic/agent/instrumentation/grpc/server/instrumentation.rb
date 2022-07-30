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

          DT_HEADERS = [NewRelic::NEWRELIC_KEY, NewRelic::TRACEPARENT_KEY, NewRelic::TRACESTATE_KEY].freeze
          INSTANCE_VAR_HOST = :@host_nr
          INSTANCE_VAR_PORT = :@port_nr
          INSTANCE_VAR_METHOD = :@method_nr

          def handle_with_tracing(streamer_type, active_call, mth, _inter_ctx)
            return yield unless trace_with_newrelic?

            metadata = metadata_for_call(active_call)
            result_code = 0
            options = trace_options(metadata, streamer_type)
            txn = NewRelic::Agent::Transaction.start_new_transaction(NewRelic::Agent::Tracer.state,
              options[:category],
              options)
            process_distributed_tracing_headers(metadata)

            begin
              yield
            rescue => e
              # TODO: report error if configured to do so
              # TODO: obtain result code
              NewRelic::Agent.notice_error(e)
              raise
            end
          ensure
            # TODO: update txn with the result code
            txn.finish if txn
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

          def grpc_headers(metadata)
            metadata.reject { |k, v| DT_KEYS.include?(k) }
          end

          def grpc_params(metadata, streamer_type, host, port, method)
            {headers: grpc_headers(metadata),
             uri: "grpc://#{host}:#{port}/#{method}",
             method: method,
             type: streamer_type}
          end

          def trace_options(metadata, streamer_type)
            host = instance_variable_get(INSTANCE_VAR_HOST)
            port = instance_variable_get(INSTANCE_VAR_PORT)
            method = instance_variable_get(INSTANCE_VAR_METHOD)
            {category: :web,
             transaction_name: "Controller/#{method}",
             filtered_params: grpc_params(metadata, streamer_type, host, port, method)}
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
