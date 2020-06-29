# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::InfiniteTracing::Config.should_load?

  module NewRelic::Agent::InfiniteTracing

    class BaseInfiniteTracer < Com::Newrelic::Trace::V1::IngestService::Service
      attr_reader :spans
      attr_reader :seen

      def initialize
        @seen = 0
        @active_calls = []
        @lock = Mutex.new
        @noticed = ConditionVariable.new
      end

      # Spans are tracked in the ServerContext object now so they can accumulate
      # regardless of which Tracer is in play.
      def set_server_context server_context
        @server_context = server_context
      end

      def notice_span span
        @lock.synchronize do
          @seen += 1
          @server_context.spans << span if defined?(@server_context)
          @noticed.signal
        end
      end

      def record_status
        Com::Newrelic::Trace::V1::RecordStatus.new(messages_seen: seen)
      end

      def wait_for_notice
        @lock.synchronize do
          @noticed.wait(@lock) if !@noticed
        end
      end

    end

    class InfiniteTracer < BaseInfiniteTracer
      def record_span(record_spans)
        span_handler = RecordSpanHandler.new(self, record_spans, @active_calls.size + 1)
        @active_calls << span_handler
        span_handler.enumerator
      end
    end

    class OkCloseInfiniteTracer < BaseInfiniteTracer
      def record_span(record_spans)
        record_spans.each{ |span| notice_span span }
        [record_status]
      end
    end

    class ErroringInfiniteTracer < BaseInfiniteTracer
      def initialize
        super
        @first_attempt = true
      end

      def record_span(record_spans)
        if @first_attempt
          msg = "You shall not pass!"
          error = GRPC::PermissionDenied.new(details = msg)
          @first_attempt = false
          raise error
        else
          span_handler = RecordSpanHandler.new(self, record_spans, @active_calls.size + 1)
          @active_calls << span_handler
          span_handler.enumerator
        end
      end
    end

    class UnimplementedInfiniteTracer < BaseInfiniteTracer
      def record_span(record_spans)
        @lock.synchronize { @noticed.signal }
        msg = "I don't exist!"
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNIMPLEMENTED, msg)
      end
    end

    class FakeTraceObserverServer
      attr_reader :trace_observer, :worker

      def initialize(port_no, tracer_class=InfiniteTracer)
        @port_no = port_no
        @tracer_class = tracer_class
        start
      end

      def set_server_context server_context
        @tracer.set_server_context server_context
      end

      def server_options
        {
          pool_size: 10,
          max_waiting_requests: 10,
          server_args: {
            'grpc.so_reuseport' => 0, # eliminates chance of cross-talks
          }
        }
      end

      def start
        @rpc_server = GRPC::RpcServer.new(**server_options)
        @port = add_http2_port
        @tracer = @tracer_class.new
        @rpc_server.handle(@tracer)
        @worker = nil
      end

      # A simple debug helper that returns list of server context statuses.
      # When there are intermittent errors happening, usually, instead of seeing
      # everything in :stopped state, we'll see one or more server contexts in
      # :running state.  
      #
      # This is our hint to research into what's not being shutdown properly!
      def running_contexts
        contexts = FakeTraceObserverHelpers::RUNNING_SERVER_CONTEXTS
        contexts.map{|k,v| v}.inspect
      end

      def add_http2_port
        retries = 0
        begin
          @rpc_server.add_http2_port("0.0.0.0:#{@port_no}", :this_port_is_insecure)
        rescue RuntimeError => error
          raise unless error.message =~ /could not add port/
          retries += 1
          raise "ran out of retries #{running_contexts}" if retries > 5
          sleep(0.05)
          retry
        end
      end

      def spans
        @tracer.spans
      end

      def wait_for_notice
        @tracer.wait_for_notice
      end

      def run
        @worker = NewRelic::Agent::InfiniteTracing::Worker.new("Server") { @rpc_server.run }
        @rpc_server.wait_till_running
      end

      def restart
        stop
        start
        run
      end

      def stop_worker
        return unless @worker
        @worker.join(2)
        @worker.stop
        @worker = nil
      end

      def stop
        @rpc_server.stop
        stop_worker
      end
    end
  end

else
  puts "Skipping tests in #{__FILE__} because Infinite Tracing is not configured to load"
end
