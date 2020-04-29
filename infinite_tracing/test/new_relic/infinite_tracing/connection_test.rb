# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      
      class Connection
        def self.reset
          @@instance = nil
        end
      end

      class ConnectionTest < Minitest::Test

        FAKE_SERVER_PORT = 10_000

        def setup
          @threads = {}
          NewRelic::Agent.instance.stubs(:start_worker_thread)
          @response_handler = ::NewRelic::Agent::Connect::ResponseHandler.new(
            NewRelic::Agent.instance,
            NewRelic::Agent.config
          )
          @agent = NewRelic::Agent.instance
          @agent.service.agent_id = 666
        end

        def teardown
          Connection.reset
          reset_buffers_and_caches
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

            simulate_connect_to_collector(fiddlesticks_config, 0.0) do |simulator|
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

              assert_watched_threads_finished
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

        # Used to emulate when a force reconnect
        # happens and a new agent run token is presented.
        def simulate_reconnect_to_collector config
          # TODO: Handle stubbing connected in the tests themselves,
          # or come up with some other solution, because otherwise
          # mocha complains
          NewRelic::Agent.instance.stubs(:connected?).returns(true)
          @response_handler.configure_agent config
        end

        private

        def assert_watched_threads_finished
          @threads.each do |thread_name, thread|
            refute thread.alive?, "Thread #{thread_name} is still alive!"
          end
        end

        def process_threads
          @threads.each(&:join)
        end

        def watch_thread name, &block
          @threads[name] = Thread.new(&block)
        end

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
            client = Client.new
            simulate_connect_to_collector fake_server_config

            segments = []
            count.times do |index|
              with_segment do |segment|
                segments << segment
                client << segment
              end
            end
            client.flush
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
