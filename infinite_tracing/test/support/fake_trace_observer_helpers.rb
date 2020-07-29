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
          @events[event].select{|e| e.inspect =~ /infinite_tracing/}
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
              timeout_cap(3.0) do
                while Thread.list.select{|t| t.status == "run"}.size > 1
                  sleep(0.01)
                end
                sleep(0.01)
              end
            end

            def flush count=0
              wait_for_agent_infinite_tracer_thread_to_close
              @lock.synchronize do
                @flushed = true
              end
            end

            def restart tracer_class=nil
              @tracer_class = tracer_class unless tracer_class.nil?
              flush
              stop
              start
            end
          end
          
          def restart_fake_trace_observer_server context, tracer_class=nil
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
          def simulate_connect_to_collector config, delay=0.01
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
            NewRelic::Agent::InfiniteTracing::Client.any_instance.stubs(:handle_close).returns(nil) unless tracer_class == OkCloseInfiniteTracer
            client = nil
            server = nil

            with_config fake_server_config do
              simulate_connect_to_collector fake_server_config do |simulator|
                # starts server and simulated agent connection
                server = ServerContext.new FAKE_SERVER_PORT, tracer_class
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
                    block.call(client, segments, server) if block_given?
                  end
                end

                # ensures all segments consumed then returns the
                # spans the server saw along with the segments sent
                client.flush
                server.flush count
                return server.spans, segments
              end
            end
          ensure
            client.stop unless client.nil?
            server.stop unless server.nil?
          end

          def emulate_streaming_segments count, max_buffer_size=100_000, &block
            emulate_streaming_with_tracer InfiniteTracer, count, max_buffer_size, &block
          end

          def emulate_streaming_to_unimplemented count, max_buffer_size=100_000, &block
            emulate_streaming_with_tracer UnimplementedInfiniteTracer, count, max_buffer_size, &block
          end

          def emulate_streaming_with_initial_error count, max_buffer_size=100_000, &block
            emulate_streaming_with_tracer ErroringInfiniteTracer, count, max_buffer_size, &block
          end

          def emulate_streaming_with_ok_close_response count, max_buffer_size=100_000, &block
            emulate_streaming_with_tracer OkCloseInfiniteTracer, count, max_buffer_size, &block
          end

          # This helper is used to setup and teardown streaming to the fake trace observer
          # A block that generates segments is expected and yielded to by this methd
          # The spans collected by the server are returned for further inspection
          def generate_and_stream_segments
            NewRelic::Agent::InfiniteTracing::Client.any_instance.stubs(:handle_close).returns(nil) 
            unstub_reconnection
            server_context = nil
            with_config fake_server_config do
              # Suppresses intermittent fails from server not ready to accept streaming
              # (the retry loop goes _much_ faster)
              Connection.instance.stubs(:retry_connection_period).returns(0.01)
              nr_freeze_time

              simulate_connect_to_collector fake_server_config do |simulator|
                # starts server and simulated agent connection
                server_context = ServerContext.new FAKE_SERVER_PORT, InfiniteTracer
                simulator.join

                yield

                # ensures all segments consumed
                NewRelic::Agent.agent.infinite_tracer.flush
                server_context.flush
                server_context.stop

                return server_context.spans
              ensure
                Connection.instance.unstub(:retry_connection_period)
                NewRelic::Agent.agent.infinite_tracer.stop
                server_context.stop unless server_context.nil?
                reset_infinite_tracer
                nr_unfreeze_time
              end
            end
          end

        end
      end
    end
  end

end
