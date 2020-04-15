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
          NewRelic::Agent.drop_buffered_data
          NewRelic::Agent.reset_config
          NewRelic::Agent.instance.stubs(:start_worker_thread)
        end

        def teardown
          reset_buffers_and_caches
        end

        def default_config
          { 
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "localhost:80"
          }
        end

        def test_tracks_agent_id_assignments
          response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
              NewRelic::Agent.instance, NewRelic::Agent.config)

          config = {
            'agent_run_id' => 'fishsticks',
            'collect_traces' => true,
            'collect_errors' => true,
            'sample_rate' => 10,
            'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
          }

          client = Client.new
          with_config_low_priority(config) do
            assert_nil NewRelic::Agent.agent.service.agent_id
            with_server_source 'agent_run_id' => 'Foo' do
              response_handler.configure_agent('agent_run_id' => 'Foo')
              # NewRelic::Agent.config.notify_server_source_added
              assert_equal "Foo", NewRelic::Agent.agent.service.agent_id
            end
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
        def test_streams_single_segment
          buffer, segments = emulate_streaming_segments 1

          buffer.each do |span|
            assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span
            assert_equal segments[0].transaction.trace_id, span["trace_id"]
          end

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1}
          })
        end

        def test_streams_multiple_segments
          buffer, segments = emulate_streaming_segments 5

          spans = buffer.map(&:itself)

          assert_equal 5, spans.size
          spans.each{ |span| assert_kind_of NewRelic::Agent::InfiniteTracing::Span, span }

          refute_metrics_recorded(["Supportability/InfiniteTracing/Span/AgentQueueDumped"])
          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 5},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 5}
          })
        end

        def test_drops_queue_when_max_reached
          buffer, segments = emulate_streaming_segments 9, 4

          spans = buffer.map(&:itself)

          assert_equal 1, spans.size
          assert_equal segments[-1].transaction.trace_id, spans[0]["trace_id"]
          assert_equal segments[-1].transaction.trace_id, spans[0]["intrinsics"]["traceId"].string_value

          assert_metrics_recorded({
            "Supportability/InfiniteTracing/Span/Seen" => {:call_count => 9},
            "Supportability/InfiniteTracing/Span/Sent" => {:call_count => 1},
            "Supportability/InfiniteTracing/Span/AgentQueueDumped" => {:call_count => 2}
          })
        end

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
