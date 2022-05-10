# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class AgentIntegrationTest < Minitest::Test
        include FakeTraceObserverHelpers

        def test_injects_infinite_tracer
          assert ::NewRelic::Agent.instance, "expected to get an Agent instance"
          assert ::NewRelic::Agent.instance.infinite_tracer
        end

        def test_streams_multiple_segments
          NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
          total_spans = 5

          spans = create_grpc_mock
          with_config fake_server_config do
            simulate_connect_to_collector fake_server_config do |simulator|
              simulator.join

              # starts client and streams count segments
              segments = []
              total_spans.times do |index|
                with_segment do |segment|
                  segments << segment
                  NewRelic::Agent.agent.infinite_tracer << deferred_span(segment)
                end
              end

              # This ensures that the mock server thread is able to complete processing before asserting starts
              simulate_server_response
              wait_for_mock_server_process

              # ensures all segments consumed
              NewRelic::Agent.agent.infinite_tracer.flush
              join_grpc_mock

              assert_equal total_spans, spans.size
              assert_equal total_spans, segments.size
            end
          end
        ensure
          Connection.instance.unstub(:retry_connection_period)
          NewRelic::Agent.agent.infinite_tracer.stop
        end
      end
    end
  end
end
