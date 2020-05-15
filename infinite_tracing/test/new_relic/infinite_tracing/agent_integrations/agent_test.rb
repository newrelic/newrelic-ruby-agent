# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../../test_helper', __FILE__)

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
          total_spans = 5
          with_config fake_server_config do
            # Suppresses intermittent fails from server not ready to accept streaming
            Connection.instance.stubs(:get_retry_connection_period).returns(0.01)

            simulate_connect_to_collector fake_server_config do |simulator|
              # starts server and simulated agent connection
              start_fake_trace_observer_server InfiniteTracer
              simulator.join

              # starts client and streams count segments
              segments = []
              total_spans.times do |index|
                with_segment do |segment|
                  segments << segment
                  NewRelic::Agent.agent.infinite_tracer << deferred_span(segment)
                end
              end

              # ensures all segments consumed
              NewRelic::Agent.agent.infinite_tracer.flush
              @server.flush total_spans
        
              assert_equal total_spans, @server.spans.size
              assert_equal total_spans, segments.size
            end
          end

        ensure
          Connection.instance.unstub(:get_retry_connection_period)
          stop_fake_trace_observer_server
        end
      end
    end
  end
end
