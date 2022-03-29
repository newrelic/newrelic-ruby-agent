# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::InfiniteTracing::Config.should_load?

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

          # ServerContext lets us centralize starting/stopping the Fake Trace Observer Server
          # and track spans the server receives across multiple Tracers and Server restarts.
          # One ServerContext instance per unit test is expected and is in play for
          # the duration of the unit test.
          class ServerContext
            attr_reader :port
            attr_reader :tracer_class
            attr_reader :server
            attr_reader :spans

            def initialize port, tracer_class
              @port = port
              @tracer_class = tracer_class
              @lock = Mutex.new
              @spans = []
              start
            end

            def start
              @lock.synchronize do
                @flushed = false
                @server = FakeTraceObserverServer.new port, tracer_class
                @server.set_server_context self
                @server.run
                RUNNING_SERVER_CONTEXTS[self] = :running
              end
            end

            def stop
              @lock.synchronize do
                @server.stop
                RUNNING_SERVER_CONTEXTS[self] = :stopped
              end
            end

            def wait_for_notice
              @server.wait_for_notice
            end

            # We really shouldn't have to sleep, but this workaround gets us past
            # various intermittent failing tests.  At the core of this issue is that
            # in the agent_integrations/agent, we call Client.start_streaming in a thread
            # This is the thread that lingers in "run" state alongside our active test runner.
            # Various attempts to join or explicitly kill this thread led to more errors
            # rather than fewer.  On the other hand, simply sleeping when there's more than
            # one Thread in a "run" state solves the issues altogether.
            def wait_for_agent_infinite_tracer_thread_to_close
              # timeout_cap(3.0) do
              #   while Thread.list.select { |t| t.status == "run" }.size > 1
              #     sleep(0.01)
              #   end
              #   sleep(0.01)
              # end
            end

            def flush count = 0
              wait_for_agent_infinite_tracer_thread_to_close
              @lock.synchronize do
                @flushed = true
              end
            end

            def restart tracer_class = nil
              @tracer_class = tracer_class unless tracer_class.nil?
              flush
              stop
              start
            end
          end

          def restart_fake_trace_observer_server context, tracer_class = nil
            context.restart tracer_class
          end

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
            # NewRelic::Agent::InfiniteTracing::Client.any_instance.stubs(:handle_close).returns(nil) unless tracer_class == OkCloseInfiniteTracer
            client = nil
            # server = nil

            with_config fake_server_config do
              simulate_connect_to_collector fake_server_config do |simulator|
                # starts server and simulated agent connection
                # server = ServerContext.new FAKE_SERVER_PORT, tracer_class
                simulator.join

                # starts client and streams count segments
                client = Client.new
                client.start_streaming

                segments = []
                count.times do |index|
                  with_segment do |segment|
                    # puts "#{Thread.current.object_id} adding segment"
                    segments << segment
                    client << deferred_span(segment)

                    # If you want opportunity to do something after each segment
                    # is pushed, invoke this method with a block and do it.
                    # block.call(client, segments, server) if block_given?
                    block.call(client, segments) if block_given?

                    # waits for the grpc mock server to handle any values it needs to
                    # puts "#{Thread.current.object_id}  before waiting emu"
                    sleep 0.01 if !@server_response_enum.empty?
                    # puts "#{Thread.current.object_id}  after waiting emu"
                  end
                end
                # waits for the mock grpc server to finish
                # puts "#{Thread.current.object_id}  before waiting emu2"
                sleep 0.1 if !@server_response_enum.empty?
                # puts "#{Thread.current.object_id}  after waiting emu2"

                # ensures all segments consumed then returns the
                # spans the server saw along with the segments sent
                client.flush
                # puts "#{Thread.current.object_id}  after client flush "

                # server.flush count
                # return server.spans, segments
                return segments
              end
            end
          ensure
            # puts "#{Thread.current.object_id}  before client stop "
            client.stop unless client.nil?
            # puts "#{Thread.current.object_id}  after client stop "

            # server.stop unless server.nil?
          end

          # class to handle the responses to the client from the server
          class ServerResponseSimulator
            def initialize
              @buffer = Queue.new
            end

            def << value
              @buffer << value
            end

            def empty?
              @buffer.empty?
            end

            def enumerator
              return enum_for(:enumerator) unless block_given?
              loop do
                if return_value = @buffer.pop(false)
                  # grpc raises any errors it gets rather than yielding them, this mimics that behavior
                  if return_value.is_a?(GRPC::BadStatus) && !return_value.is_a?(GRPC::Ok)
                    raise return_value
                  end
                  yield return_value
                end
              end
            end
          end

          # def shutdown_grpc_mock
          #   # allows the test to finish what its doing on other threads before shutting down the mock server thread
          #   sleep 0.1 if !@server_response_enum.empty?
          #   @mock_thread.kill
          # end

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

          ## &block = code we want to execute on "SERVER" thread
          def create_grpc_mock(simulate_broken_server: false, expect_mock: true, &block)
            seen_spans = [] # array of how many spans our mock sees
            @mock_thread = nil # keep track of the thread for our mock server

            @server_response_enum = ServerResponseSimulator.new

            mock_rpc = mock()
            expectation = expect_mock ? :at_least_once : :never
            # stubs out the record_span to keep track of what the agent passes to grpc (and bypass using grpc in the tests)
            mock_rpc.expects(:record_span).send(expectation).with do |enum, metadata|
              @mock_thread = Thread.new do
                # puts "mock: class #{enum.class}"
                enum.each do |span|
                  break if span.nil?
                  # puts "#{Thread.current.object_id} in mock server   #{span.trace_id}"
                  seen_spans << span unless span.nil? || simulate_broken_server
                  # block.call(seen_spans) if block_given? # do we even need this???
                end
              end
            end.returns(@server_response_enum.enumerator)

            NewRelic::Agent::InfiniteTracing::Channel.any_instance.stubs('stub').returns(mock_rpc)
            return seen_spans
          end

          def join_grpc_mock
            @mock_thread.join if @mock_thread
          end

          def mock_response
            @mock_response ||= mock().tap do |mock_response|
              mock_response.stubs(:messages_seen).returns(1)
            end
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
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, segments|
              simulate_server_response_shutdown GRPC::Unimplemented.new
              active_client = client
            end
            join_grpc_mock
            return spans, segments, active_client
          end

          def emulate_streaming_to_failed_precondition count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock(simulate_broken_server: true)
            active_client = nil
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, segments|
              simulate_server_response_shutdown GRPC::FailedPrecondition.new
              active_client ||= client
            end
            join_grpc_mock
            return spans, segments, active_client
          end

          def emulate_streaming_with_initial_error count, max_buffer_size = 100_000, &block
            spans = create_grpc_mock
            first = true
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, segments|
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
            segments = emulate_streaming_with_tracer nil, count, max_buffer_size do |client, segments|
              simulate_server_response GRPC::Ok.new
            end
            join_grpc_mock
            return spans, segments
          end

          # This helper is used to setup and teardown streaming to the fake trace observer
          # A block that generates segments is expected and yielded to by this methd
          # The spans collected by the server are returned for further inspection
          def generate_and_stream_segments(expect_mock: true)
            # NewRelic::Agent::InfiniteTracing::Client.any_instance.stubs(:handle_close).returns(nil)
            unstub_reconnection
            server_context = nil
            spans = create_grpc_mock(expect_mock: expect_mock)
            with_config fake_server_config do
              # Suppresses intermittent fails from server not ready to accept streaming
              # (the retry loop goes _much_ faster)
              Connection.instance.stubs(:retry_connection_period).returns(0.01)
              nr_freeze_time
              nr_freeze_process_time

              simulate_connect_to_collector fake_server_config do |simulator|
                # starts server and simulated agent connection
                # server_context = ServerContext.new FAKE_SERVER_PORT, InfiniteTracer
                simulator.join

                yield

                # ensures all segments consumed
                NewRelic::Agent.agent.infinite_tracer.flush
                # server_context.flush
                # server_context.stop

                # return server_context.spans
                return spans
              ensure
                Connection.instance.unstub(:retry_connection_period)
                NewRelic::Agent.agent.infinite_tracer.stop
                join_grpc_mock
                # server_context.stop unless server_context.nil?
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
