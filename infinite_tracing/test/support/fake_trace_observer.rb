# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::InfiniteTracing::Config.should_load?

  module NewRelic::Agent::InfiniteTracing

    class InfiniteTracer < Com::Newrelic::Trace::V1::IngestService::Service
      attr_reader :spans
      attr_reader :seen

      def initialize
        @seen = 0
        @spans = []
        @active_calls = []
        @lock = Mutex.new
        @noticed = ConditionVariable.new
      end

      def notice_span span
        @lock.synchronize do
          @seen += 1
          @spans << span
          @noticed.signal
        end
      end

      def record_span(record_spans)
        span_handler = RecordSpanHandler.new(self, record_spans, @active_calls.size + 1)
        @active_calls << span_handler
        span_handler.enumerator
      end
    end

    class UnimplementedInfiniteTracer < Com::Newrelic::Trace::V1::IngestService::Service
      attr_reader :spans
      attr_reader :seen

      def initialize
        @seen = 0
        @spans = []
        @active_calls = []
        @lock = Mutex.new
        @noticed = ConditionVariable.new
        @waited = false
      end

      def notice_span span
        @lock.synchronize do
          @seen += 1
          @spans << span
          @noticed.signal
        end
      end

      # TODO: this may not be useful
      def wait_for_notice
        return if @waited
        @lock.synchronize do
          @noticed.wait(@lock)
          @waited = true
        end
        Thread.pass
      end

      def record_span(record_spans)
        @lock.synchronize { @noticed.signal }
        msg = "You shall not pass!"
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

      def server_options
        {
          pool_size: 10, 
          max_waiting_requests: 10,
          server_args: {
            'grpc.so_reuseport' => 0, # eliminsates chance of cross-talks
          }
        }
      end

      def start
        @server = GRPC::RpcServer.new(**server_options)
        @port = @server.add_http2_port("0.0.0.0:#{@port_no}", :this_port_is_insecure)
        @tracer = @tracer_class.new
        @server.handle(@tracer)
        @worker = nil
      end

      def spans
        @tracer.spans
      end

      def flush expected
        # TODO: helps stop intermittent failures.  Can we eliminate by actually detecting when
        # server finishes process all inbound data and is closing it's stream?
        sleep(0.01)
      end

      def wait_for_notice
        @tracer.wait_for_notice
      end

      def run
        @worker = NewRelic::Agent::InfiniteTracing::Worker.new("Server") { @server.run }
        @server.wait_till_running
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
        @server.stop
        stop_worker
      end
    end
  end

else
  puts "Skipping tests in #{__FILE__} because Infinite Tracing is not configured to load"
end
