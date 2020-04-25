# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class ClientTest < Minitest::Test

        FAKE_SERVER_PORT = 10_000

        def setup
          NewRelic::Agent.instance.stubs(:start_worker_thread)
          @response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
            NewRelic::Agent.instance,
            NewRelic::Agent.config
          )
          @agent = NewRelic::Agent.instance
          @agent.service.agent_id = 666
        end

        def teardown
          reset_buffers_and_caches
        end

        def test_config
          {
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "localhost:80",
            :'license_key' => "swiss_cheese"
          }
        end

        def fake_server_config
          {
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "localhost",
            :'infinite_tracing.trace_observer.port' => FAKE_SERVER_PORT,
            :'license_key' => "swiss_cheese"
          }
        end

        def fiddlesticks_config
          {
            'agent_run_id' => 'fiddlesticks',
            'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
          }
        end

        def reconnect_config
          {
            'agent_run_id' => 'shazbat',
            'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
          }
        end

        # simulates applying a server-side config to the agent instance.
        # the sleep 0.01 allows us to choose whether to join and wait
        # or set it up and continue with test scenario's flow.
        def simulate_connect_to_collector config
          Thread.new do
            sleep(0.01)
            # TODO: Handle stubbing connected in the tests themselves,
            # or come up with some other solution, because otherwise
            # mocha complains
            NewRelic::Agent.instance.stubs(:connected?).returns(true)
            @response_handler.configure_agent config
          end
        end

        # Used to emulate when a force reconnect
        # happens and a new agent run token is presented.
        def simulate_reconnect_to_collector config
          # TODO: Handle stubbing connected in the tests themselves,
          # or come up with some other solution, because otherwise
          # mocha complains
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          @response_handler.configure_agent config
        end

        # This scenario tests client being intialized before the agent
        # begins it's connection handshake.
        # def test_client_initialized_before_connecting
        #   with_config test_config do

        #     client = Client.new
        #     simulate_connect_to_collector fiddlesticks_config

        #     metadata = client.send :metadata
        #     assert_equal "swiss_cheese", metadata["license_key"]
        #     assert_equal "fiddlesticks", metadata["agent_run_token"]
        #   end
        # end

        # This scenario tests that agent _can_ be connected before client
        # is instantiated.
        # def test_client_initialized_after_connecting
        #   with_config test_config do

        #     simulate_connect_to_collector(fiddlesticks_config).join
        #     client = Client.new

        #     metadata = client.send :metadata
        #     assert_equal "swiss_cheese", metadata["license_key"]
        #     assert_equal "fiddlesticks", metadata["agent_run_token"]
        #   end
        # end

        # This scenario tests that the agent is connecting _after_
        # the client is instantiated (via sleep 0.01 w/o explicit join).
        # def test_client_initialized_after_connecting_and_waiting
        #   with_config test_config do

        #     simulate_connect_to_collector fiddlesticks_config
        #     client = Client.new

        #     metadata = client.send :metadata
        #     assert_equal "swiss_cheese", metadata["license_key"]
        #     assert_equal "fiddlesticks", metadata["agent_run_token"]
        #   end
        # end

        # Tests making an initial connection and then reconnecting.
        # The metadata is expected to change since agent run token changes.
        # def test_client_reconnects
        #   with_config test_config do
        #     client = Client.new
        #     simulate_connect_to_collector(fiddlesticks_config).join

        #     metadata = client.send :metadata
        #     assert_equal "swiss_cheese", metadata["license_key"]
        #     assert_equal "fiddlesticks", metadata["agent_run_token"]

        #     simulate_reconnect_to_collector(reconnect_config)

        #     metadata = client.send :metadata
        #     assert_equal "swiss_cheese", metadata["license_key"]
        #     assert_equal "shazbat", metadata["agent_run_token"]
        #   end
        # end

        def test_streams_single_segment
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          spans, segments = emulate_streaming_segments 1

          spans.each do |span|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal segments[0].transaction.trace_id, span["trace_id"]
          end

          assert_equal 1, spans.size

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
          })
        end

        # def test_streams_multiple_segments
        #   buffer, segments = emulate_streaming_segments 5

        #   spans = buffer.map(&:itself)

        #   assert_equal 5, spans.size
        #   spans.each{ |span| assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span }

        #   refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
        #   assert_metrics_recorded({
        #     "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
        #     "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
        #   })
        # end

        # def test_drops_queue_when_max_reached
        #   buffer, segments = emulate_streaming_segments 9, 4

        #   spans = buffer.map(&:itself)

        #   assert_equal 1, spans.size
        #   assert_equal segments[-1].transaction.trace_id, spans[0]["trace_id"]
        #   assert_equal segments[-1].transaction.trace_id, spans[0]["intrinsics"]["traceId"].string_value

        #   assert_metrics_recorded({
        #     "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 9},
        #     "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1},
        #     "Supportability/InfiniteTracing/Span/AgentQueueDumped" => {:call_count => 2}
        #   })
        # end

        private

        def start_fake_trace_observer_server
          @server = NewRelic::InfiniteTracing::FakeTraceObserverServer.new FAKE_SERVER_PORT
          @server.start
        end

        def stop_fake_trace_observer_server
          return unless @server
          @server.stop
        end

        def emulate_streaming_segments count, max_buffer_size=100_000
          start_fake_trace_observer_server
          with_config fake_server_config do
            client = Client.new FAKE_SERVER_PORT
            simulate_connect_to_collector fake_server_config

            segments = []
            count.times do |index|
              with_segment do |segment|
                segments << segment
                client << segment
              end
            end
            return @server.spans, segments
          end
        rescue => e
          puts "ERROR: #{e.inspect}"
          puts e.backtrace
        ensure
          stop_fake_trace_observer_server
        end

      end
    end
  end
end
