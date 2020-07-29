# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

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
          server = nil

          with_config fake_server_config do
            # Suppresses intermittent fails from server not ready to accept streaming
            Connection.instance.stubs(:retry_connection_period).returns(0.01)

            simulate_connect_to_collector fake_server_config do |simulator|
              # starts server and simulated agent connection
              server = ServerContext.new FAKE_SERVER_PORT, InfiniteTracer
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
              server.flush total_spans

              assert_equal total_spans, server.spans.size
              assert_equal total_spans, segments.size
            end
          end

        ensure
          Connection.instance.unstub(:retry_connection_period)
          NewRelic::Agent.agent.infinite_tracer.stop
          server.stop unless server.nil?
        end
      end
    end
  end
end
