# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class ClientTest < Minitest::Test

        def setup
          NewRelic::Agent.instance.stubs(:start_worker_thread)
          @response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
            NewRelic::Agent.instance, 
            NewRelic::Agent.config
          )
        end

        def teardown
          reset_buffers_and_caches
        end

        def default_config
          { 
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "localhost:80",
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
            NewRelic::Agent.instance.stubs(:connected?).returns(true)
            @response_handler.configure_agent config
          end
        end

        # Used to emulate when a force reconnect
        # happens and a new agent run token is presented.
        def simulate_reconnect_to_collector config
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          @response_handler.configure_agent config
        end

        # This scenario tests client being intialized before the agent
        # begins it's connection handshake.
        def test_client_initialized_before_connecting
          with_config default_config do

            client = Client.new
            simulate_connect_to_collector fiddlesticks_config

            assert_equal "swiss_cheese", client.metadata["license_key"]
            assert_equal "fiddlesticks", client.metadata["agent_run_token"]
          end
        end

        # This scenario tests that agent _can_ be connected before client
        # is instantiated.
        def test_client_initialized_after_connecting
          with_config default_config do

            simulate_connect_to_collector(fiddlesticks_config).join
            client = Client.new
            
            assert_equal "swiss_cheese", client.metadata["license_key"]
            assert_equal "fiddlesticks", client.metadata["agent_run_token"]
          end
        end

        # This scenario tests that the agent is connecting _after_
        # the client is instantiated (via sleep 0.01 w/o explicit join).
        def test_client_initialized_after_connecting_and_waiting
          with_config default_config do

            simulate_connect_to_collector fiddlesticks_config
            client = Client.new
            
            assert_equal "swiss_cheese", client.metadata["license_key"]
            assert_equal "fiddlesticks", client.metadata["agent_run_token"]
          end
        end

        # Tests making an initial connection and then reconnecting.
        # The metadata is expected to change since agent run token changes.
        def test_client_reconnects
          with_config default_config do
            client = Client.new
            simulate_connect_to_collector(fiddlesticks_config).join

            assert_equal "swiss_cheese", client.metadata["license_key"]
            assert_equal "fiddlesticks", client.metadata["agent_run_token"]

            simulate_reconnect_to_collector(reconnect_config)

            assert_equal "swiss_cheese", client.metadata["license_key"]
            assert_equal "shazbat", client.metadata["agent_run_token"]
          end
        end

        #   client = Client.new
        #   assert_nil client.agent_id, "Agent ID expected to be nil until Agent connects"
        #   with_config default_config do
        #     with_server_source 'agent_run_id' => "foo" do

        #       assert_equal "foo", client.agent_id
        #     end
        #   end
        # end

        # NOTE: these tests may likely survive unchanged!
        # def test_streams_single_segment
        #   buffer, segments = emulate_streaming_segments 1

        #   buffer.each do |span|
        #     assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
        #     assert_equal segments[0].transaction.trace_id, span["trace_id"]
        #   end

        #   refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
        #   assert_metrics_recorded({
        #     "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
        #     "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
        #   })
        # end

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

        def emulate_streaming_segments count, max_buffer_size=100_000
          # TODO: Change this to stream through the client to the fake trace observer
          buffer = StreamingBuffer.new max_buffer_size
          segments = []
          count.times do |index|
            with_segment do |segment|
              segments << segment
              buffer << segment
            end
          end
          Thread.new { buffer.finish }
          return buffer, segments
        end

      end
    end
  end
end
