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
      end

      def notice_span span
        @seen += 1
        @spans << span
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
      end

      def notice_span span
        @seen += 1
        @spans << span
      end

      def record_span(record_spans)
        msg = "You shall not pass!"
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::UNIMPLEMENTED, msg)
      end
    end

    class FakeTraceObserverServer
      attr_reader :trace_observer, :worker

      def initialize(port, tracer_class=InfiniteTracer)
        @server = GRPC::RpcServer.new(pool_size: 24, max_waiting_requests: 24)
        @port = @server.add_http2_port("0.0.0.0:#{port}", :this_port_is_insecure)
        @tracer = tracer_class.new
        @server.handle(@tracer)
        @worker = nil
      end

      def spans
        @tracer.spans
      end

      def run
        @worker = NewRelic::Agent::InfiniteTracing::Worker.new "Server" do
          @server.run
        end
        @server.wait_till_running
      end

      def restart
        stop
        @server = GRPC::RpcServer.new(pool_size: 24, max_waiting_requests: 24)
        @tracer = InfiniteTracer.new
        @server.handle(@tracer)
        run
      end

      def stop_worker
        return unless @worker
        @worker.stop
        @worker = nil
      end

      def stop
        @server.stop
        @worker.join(2)
        stop_worker
      end
    end
  end

else
  puts "Skipping tests in #{__FILE__} because Infinite Tracing is not configured to load"
end
