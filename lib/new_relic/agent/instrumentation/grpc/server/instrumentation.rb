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
            ::NewRelic::Agent::DistributedTracing::accept_distributed_trace_headers(trace_headers, 'Other') if ::NewRelic::Agent.config[:'distributed_tracing.enabled']
            yield
          end

          private

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
