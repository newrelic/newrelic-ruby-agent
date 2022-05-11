# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::InfiniteTracing::Config.should_load?
  require_relative 'server_response_simulator'

  module NewRelic
    module Agent
      # This lets us peek into the Event Listener to see what events
      # are subscribed.
      class EventListener
        def still_subscribed event
          return [] if @events[event].nil?
          @events[event].select { |e| e.inspect =~ /infinite_tracing/ }
        end
      end

      module InfiniteTracing
        module FakeTraceObserverHelpers
          FAKE_SERVER_PORT = 10_000

          def setup
            Connection.reset!
            NewRelic::Agent.instance.stubs(:start_worker_thread)
            @response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
              NewRelic::Agent.instance,
              NewRelic::Agent.config
            )
            stub_reconnection
            @agent = NewRelic::Agent.instance
            @agent.service.agent_id = 666
            @server_response_enum = nil
            @mock_thread = nil
          end

          def stub_reconnection
            Connection.any_instance.stubs(:note_connect_failure).returns(0).then.raises(NewRelic::TestHelpers::Exceptions::TestError) # reattempt once and then forcibly break out of with_reconnection_backoff
            Connection.any_instance.stubs(:retry_connection_period).returns(0)
          end

          def unstub_reconnection
            Connection.any_instance.unstub(:note_connect_failure)
            Connection.any_instance.unstub(:retry_connection_period)
          end

          def assert_only_one_subscription_notifier
            still_subscribed = NewRelic::Agent.agent.events.still_subscribed(:server_source_configuration_added)
            assert_equal 1, still_subscribed.size
          end

          def teardown
            @mock_thread.kill if @mock_thread
            @mock_thread = nil
            @server_response_enum = nil
            reset_buffers_and_caches
            assert_only_one_subscription_notifier
            reset_infinite_tracer
            unstub_reconnection
            Connection.reset!
          end

          # reset! is not used in production code and only needed for
          # testing purposes, so its implemented here
          # Must clear the @@instance between tests to ensure
          # a clean start with each test scenario
          class NewRelic::Agent::InfiniteTracing::Connection
            def self.reset!
              self.reset
              @@instance = nil
            end
          end

          RUNNING_SERVER_CONTEXTS = {}

          def localhost_config
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
              'agent_config' => {'transaction_tracer.record_sql' => 'raw'}
            }
          end

          def reconnect_config
            {
              'agent_run_id' => 'shazbat',
              'agent_config' => {'transaction_tracer.record_sql' => 'raw'}
            }
          end

          # simulates applying a server-side config to the agent instance.
          # the sleep 0.01 allows us to choose whether to join and wait
          # or set it up and continue with test scenario's flow.
          def simulate_connect_to_collector config, delay = 0.01
            thread = Thread.new do
              sleep delay
              NewRelic::Agent.instance.stubs(:connected?).returns(true)
              @response_handler.configure_agent config
            end
            yield thread
          ensure
            thread.kill
            NewRelic::Agent.instance.unstub(:connected?)
          end

          # Used to emulate when a force reconnect
          # happens and a new agent run token is presented.
          def simulate_reconnect_to_collector config
            NewRelic::Agent.instance.stubs(:connected?).returns(true)
            @response_handler.configure_agent config
          end

          def emulate_streaming_with_tracer tracer_class, count, max_buffer_size, &block
            NewRelic::Agent::Transaction::Segment.any_instance.stubs('record_span_event')
            client = nil

            with_config fake_server_config do
              simulate_connect_to_collector fake_server_config do |simulator|
                simulator.join

                # starts client and streams count segments
                client = Client.new
                client.start_streaming

                segments = []
                count.times do |index|
                  with_segment do |segment|
                    segments << segment
                    client << deferred_span(segment)

                    # If you want opportunity to do something after each segment
                    # is pushed, invoke this method with a block and do it.
                    block.call(client, segments) if block_given?

                    # waits for the grpc mock server to handle any values it needs to
                    # important for tests that expect the mock server to break at a specific point
                    wait_for_mock_server_process
                  end
                end
                # waits for the mock grpc server to finish
                wait_for_mock_server_process

                # ensures all segments consumed then returns the
                # spans the server saw along with the segments sent
                client.flush

                return segments
              end
            end
          ensure
            client.stop unless client.nil?
          end

          # when the server responds with an error that should stop the server
          def simulate_server_response_shutdown(response = GRPC::Ok.new)
            @server_response_enum << response
            # allow the test to handle the response before shutting down
            sleep 0.1 if !@server_response_enum.empty?
            @mock_thread.kill
          end

          def simulate_server_response(response = mock_response)
            @server_response_enum << response
          end

          # simulate_broken_server tells us whether we are expecting the mock server to be actually consuming spans
          # expect_mock tells us if we are expecting the mock server to actually be reached in that test
          # &block  code we want to execute on "SERVER" thread
          def create_grpc_mock(simulate_broken_server: false, expect_mock: true, &block)
            seen_spans = [] # array of how many spans our mock sees
            @mock_thread = nil # keep track of the thread for our mock server
            @server_response_enum = ServerResponseSimulator.new
            mock_rpc = mock()

            # some tests will never reach the mock grpc server
            # so this allows us to use the same structure and simply change the expectation
            expectation = expect_mock ? :at_least_once : :never

            # stubs out the record_span to keep track of what the agent passes to grpc (and bypass using grpc in the tests)
            mock_rpc.expects(:record_span).send(expectation).with do |enum, metadata|
              @mock_thread = Thread.new do
                enum.each do |span|
                  break if span.nil? # how grpc knows the stream is over
                  seen_spans << span unless span.nil? || simulate_broken_server
                end
              end
            end.returns(@server_response_enum.enumerator)

            NewRelic::Agent::InfiniteTracing::Channel.any_instance.stubs('stub').returns(mock_rpc)
            return seen_spans
          end

          def join_grpc_mock
            @mock_thread.join if @mock_thread
          end

          # Simulates a Messages seen response from the mock grpc server
          def mock_response
            @mock_response ||= mock().tap do |mock_response|
              mock_response.stubs(:messages_seen).returns(1)
            end
          end

          # This ensures that the mock grpc server has time to process what it has received before we being asserting
          def wait_for_mock_server_process
            sleep 0.1 if !@server_response_enum.empty?
          end

          def emulate_streaming_segments count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size, &block
            join_grpc_mock
            return spans, segments
          end

          def emulate_streaming_to_unimplemented count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock(simulate_broken_server: true)
            active_client = nil
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, current_segments|
              simulate_server_response_shutdown GRPC::Unimplemented.new
              active_client = client
            end
            join_grpc_mock
            return spans, segments, active_client
          end

          def emulate_streaming_to_failed_precondition count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock(simulate_broken_server: true)
            active_client = nil
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, current_segments|
              simulate_server_response_shutdown GRPC::FailedPrecondition.new
              active_client ||= client
            end
            join_grpc_mock
            return spans, segments, active_client
          end

          def emulate_streaming_with_initial_error count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock
            first = true
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, current_segments|
              if first
                # raise error only first time
                simulate_server_response_shutdown GRPC::PermissionDenied.new(details = "denied")
                first = false
              else
                simulate_server_response
              end
            end
            join_grpc_mock
            return spans, segments
          end

          def emulate_streaming_with_ok_close_response count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, current_segments|
              simulate_server_response GRPC::Ok.new
            end
            join_grpc_mock
            return spans, segments
          end

          # A block that generates segments is expected and yielded to by this methd
          def generate_and_stream_segments(expect_mock: true)
            unstub_reconnection
            spans = create_grpc_mock(expect_mock: expect_mock)
            with_config fake_server_config do
              # Suppresses intermittent fails from server not ready to accept streaming
              # (the retry loop goes _much_ faster)
              Connection.instance.stubs(:retry_connection_period).returns(0.01)
              nr_freeze_time
              nr_freeze_process_time

              simulate_connect_to_collector fake_server_config do |simulator|
                simulator.join
                yield

                # ensures all segments consumed
                NewRelic::Agent.agent.infinite_tracer.flush
                return spans
              ensure
                simulate_server_response if expect_mock
                # allow mock grpc server to finish processing what it ahs received
                wait_for_mock_server_process
                Connection.instance.unstub(:retry_connection_period)
                NewRelic::Agent.agent.infinite_tracer.stop
                join_grpc_mock
                reset_infinite_tracer
                nr_unfreeze_time
                nr_unfreeze_process_time
              end
            end
          end
        end
      end
    end
  end

end
