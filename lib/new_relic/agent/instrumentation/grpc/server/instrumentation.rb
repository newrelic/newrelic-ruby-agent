# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Server
          def initialize_with_tracing(*args)
            instance = yield
            instance.instance_variable_set(:@trace_with_newrelic, trace_with_newrelic?(args.first))
            instance
          end

          def handle_with_tracing(service)
            return yield unless trace_with_newrelic?

            yield
          end

          def run_with_tracing(signals, wait_interval)
            return yield unless trace_with_newrelic?

            yield
          end

          private

          def trace_with_newrelic?(host = nil)
            return false if self.class.name.eql?('GRPC::InterceptorRegistry')

            do_trace = instance_variable_get(:@trace_with_newrelic)
            return do_trace unless do_trace.nil?

            # TODO: preferred server filtration

            true
          end
        end
      end
    end
  end
end
