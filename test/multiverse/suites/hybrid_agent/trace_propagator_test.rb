# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Context
        module Propagation
          class TracePropagatorTest < Minitest::Test
            class FakePropError < StandardError; end

            def test_inject_calls_distributed_tracing_api
              @propagator = NewRelic::Agent::OpenTelemetry::Context::Propagation::TracePropagator.new
              fake_carrier = {}

              NewRelic::Agent::DistributedTracing.stub(:insert_distributed_trace_headers, -> (args) { raise FakePropError.new }) do
                assert_raises(FakePropError) { @propagator.inject(fake_carrier) }
              end
            end
          end
        end
      end
    end
  end
end
