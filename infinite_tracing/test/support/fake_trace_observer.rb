# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

if NewRelic::Agent::InfiniteTracing::Config.should_load?
  module NewRelic::InfiniteTracing

    # A EnumeratorQueue wraps a Queue to yield the items added to it.
    class EnumeratorQueue
      extend Forwardable
      def_delegators :@q, :push

      def initialize(sentinel)
        @q = Queue.new
        @sentinel = sentinel
      end

      def each_item
        return enum_for(:each_item) unless block_given?
        loop do
          r = @q.pop
          break if r.equal?(@sentinel)
          fail r if r.is_a? Exception
          yield r
        end
      end
    end

    class TraceObserverHandler < Com::Newrelic::Trace::V1::IngestService::Service
      attr_reader :spans, :seen

      def initialize
        @seen = 0
        @next_seen_hurdle = 10
        @spans = []
      end

      def record_span(incoming_spans, _call)
        # requests is an lazy Enumerator of the requests sent by the client.
        puts "RECORD_SPAN"
        q = EnumeratorQueue.new(self)
        t = Thread.new do
          begin
            incoming_spans.each do |span|
              puts '3'
              @spans << span
              @seen += 1
              if @seen >= @next_seen_hurdle
                @next_seen_hurdle += 10
                q.push record_status
              end
              Thread.pass  # let the internal Bidi threads run
            end
            q.push(self)
          rescue StandardError => e
            q.push(e)  # share the exception with the enumerator
            raise e
          end
        end
        t.priority = -2  # hint that the div_many thread should not be favoured
        q.each_item
      end

      def record_status
        Com::Newrelic::Trace::V1::RecordStatus.new(messages_seen: @seen)
      end

      # def handle
      #   return enum_for(:handle) unless block_given?
      #   @record_spans.each do |span|
      #     puts '3'
      #     @spans << span
      #     @seen += 1
      #     if @seen >= @next_seen_hurdle
      #       @next_seen_hurdle += 10
      #       yield record_status
      #     end
      #   end
      #   yield record_status
      # end
    end

    class FakeTraceObserverServer
      attr_reader :trace_observer, :worker

      def initialize(port)
        @server = GRPC::RpcServer.new pool_size: 10, max_waiting_requests: 255
        @port = @server.add_http2_port "localhost:#{port}", :this_port_is_insecure
        @trace_observer = TraceObserverHandler.new
        @server.handle @trace_observer
        @worker = nil
      end

      def spans
        @trace_observer.spans
      end

      def seen
        @trace_observer.seen
      end

      def start
        puts "START"
        @worker = Thread.new do
          @server.run_till_terminated_or_interrupted([1, 'int'.dup, 'SIGQUIT'.dup])
        end
        @worker.abort_on_exception
      end

      def get_port
        @port
      end

      def stop
        @server.stop
      end
    end
  end
else
  puts "Skipping tests in #{__FILE__} because Infinite Tracing is not configured to load"
end