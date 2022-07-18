# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Server
          def handle_with_tracing(active_call, mth, inter_ctx)
            return yield unless trace_with_newrelic?
            trace_headers = active_call.metadata.delete(NewRelic::NEWRELIC_KEY)
            ::NewRelic::Agent::DistributedTracing::accept_distributed_trace_headers(trace_headers, 'Other') if ::NewRelic::Agent.config[:'distirbuted_tracing.enabled']

            finishable = NewRelic::Agent::Tracer.start_transaction_or_segment(
              name: mth.original_name,
              category: :web,
              options: server_options(active_call.metadata, mth.original_name)
            )
            yield
          ensure
            finishable.finish
          end

          private

          def server_options(headers, method)
            host = 'host'
            port = 'port'
            {
              request: {
                headers: headers,
                uri: "grpc://#{host}:#{port}/#{method}",
                method: method
              }
            }
          end

          def trace_with_newrelic?(host = nil)
            # TODO: check hostname against the configured denylist
            # hostname = ::NewRelic::Agent::Hostname.get

            true
          end
        end
      end
    end
  end
end
