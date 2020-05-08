# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing

      class ConnectionTest < Minitest::Test
        include FakeTraceObserverHelpers

        # This scenario tests client being intialized before the agent
        # begins it's connection handshake.
        def test_connection_initialized_before_connecting
          timeout_cap do
            with_config localhost_config do

              connection = Connection.instance # instantiate before simulation
              simulate_connect_to_collector fiddlesticks_config, 0.01 do |simulator|
                simulator.join # ensure our simulation happens!
                metadata = connection.send :metadata

                assert_equal "swiss_cheese", metadata["license_key"]
                assert_equal "fiddlesticks", metadata["agent_run_token"]
              end
            end
          end
        end

        # This scenario tests that agent _can_ be connected before connection
        # is instantiated.
        def test_connection_initialized_after_connecting
          timeout_cap do
            with_config localhost_config do

              simulate_connect_to_collector fiddlesticks_config, 0.0 do |simulator|
                simulator.join # ensure our simulation happens!
                connection = Connection.instance # instantiate after simulated connection
                metadata = connection.send :metadata

                assert_equal "swiss_cheese", metadata["license_key"]
                assert_equal "fiddlesticks", metadata["agent_run_token"]
              end
            end
          end
        end

        # This scenario tests that the agent is connecting _after_
        # the client is instantiated (via sleep 0.01 w/o explicit join).
        def test_connection_initialized_after_connecting_and_waiting
          timeout_cap do
            with_config localhost_config do
              simulate_connect_to_collector fiddlesticks_config, 0.01 do |simulator|
                simulator.join # ensure our simulation happens!
                connection = Connection.instance
                metadata = connection.send :metadata

                assert_equal "swiss_cheese", metadata["license_key"]
                assert_equal "fiddlesticks", metadata["agent_run_token"]
              end
            end
          end
        end

        # Tests making an initial connection and then reconnecting.
        # The metadata is expected to change since agent run token changes.
        def test_connection_reconnects
          timeout_cap do
            with_config localhost_config do
              connection = Connection.instance
              simulate_connect_to_collector fiddlesticks_config, 0.0 do |simulator|
                simulator.join
                metadata = connection.send :metadata
                assert_equal "swiss_cheese", metadata["license_key"]
                assert_equal "fiddlesticks", metadata["agent_run_token"]

                simulate_reconnect_to_collector(reconnect_config)
                metadata = connection.send :metadata

                assert_equal "swiss_cheese", metadata["license_key"]
                assert_equal "shazbat", metadata["agent_run_token"]
              end
            end
          end
        end

        def test_sending_spans_to_server
          timeout_cap do
            total_spans = 5
            spans, segments = emulate_streaming_segments total_spans
            assert_equal total_spans, segments.size
            assert_equal total_spans, spans.size
          end
        end

        def test_handling_unimplemented_server_response
          timeout_cap do
            total_spans = 5
            spans, segments = emulate_streaming_to_unimplemented total_spans
            assert_equal total_spans, segments.size
            assert_equal 0, spans.size
            assert_metrics_recorded({
              "Supportability/InfiniteTracing/Span/Response/Error" => {:call_count => 1},
              "Supportability/InfiniteTracing/Span/gRPC/UNIMPLEMENTED" => {:call_count => 1}
            })
          end
        end

        # Testing the backoff similarly to connect_test.rb
        def test_increment_retry_period
          assert_equal  15, next_retry_period
          assert_equal  15, next_retry_period
          assert_equal  30, next_retry_period
          assert_equal  60, next_retry_period
          assert_equal 120, next_retry_period
          assert_equal 300, next_retry_period
          assert_equal 300, next_retry_period
          assert_equal 300, next_retry_period
        end

        private 

        def next_retry_period
          result = Connection.instance.send(:retry_connection_period)
          Connection.instance.send(:note_connect_failure)
          result
        end

      end
    end
  end
end
