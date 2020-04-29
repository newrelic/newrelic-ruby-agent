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
          with_config localhost_config do

            connection = Connection.instance
            simulate_connect_to_collector fiddlesticks_config, 0.01 do |simulator|
              metadata = connection.send :metadata
              simulator.join # ensure our simulation happens!

              assert_equal "swiss_cheese", metadata["license_key"]
              assert_equal "fiddlesticks", metadata["agent_run_token"]
            end
          end
        end

        # This scenario tests that agent _can_ be connected before connection
        # is instantiated.
        def test_connection_initialized_after_connecting
          with_config localhost_config do

            simulate_connect_to_collector fiddlesticks_config, 0.0 do |simulator|
              simulator.join
              connection = Connection.instance

              metadata = connection.send :metadata
              assert_equal "swiss_cheese", metadata["license_key"]
              assert_equal "fiddlesticks", metadata["agent_run_token"]
            end
          end
        end

        # This scenario tests that the agent is connecting _after_
        # the client is instantiated (via sleep 0.01 w/o explicit join).
        def test_connection_initialized_after_connecting_and_waiting
          with_config localhost_config do
            simulate_connect_to_collector fiddlesticks_config, 0.01 do |simulator|
              connection = Connection.instance

              metadata = connection.send :metadata
              simulator.join # ensure our simulation happens!

              assert_equal "swiss_cheese", metadata["license_key"]
              assert_equal "fiddlesticks", metadata["agent_run_token"]
            end
          end
        end

        # Tests making an initial connection and then reconnecting.
        # The metadata is expected to change since agent run token changes.
        def test_connection_reconnects
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

        def test_sending_spans_to_server
          total_spans = 5
          spans, segments = emulate_streaming_segments total_spans
          assert_equal total_spans, segments.size
          assert_equal total_spans, spans.size
        end

      end
    end
  end
end
