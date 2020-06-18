# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class RecordSpanHandler

      HURDLE_INCREMENT = 3

      def initialize server, record_spans, id
        @server = server
        @record_spans = record_spans
        @id = id
        @next_seen_hurdle = seen + HURDLE_INCREMENT
        @record_status_stream = EnumeratorQueue.new
        @lock = Mutex.new
        @lock.synchronize { @worker = start_handler }
      end

      def seen
        @server.seen
      end

      def enumerator
        @record_status_stream.each_item
      end

      def record_status
        Com::Newrelic::Trace::V1::RecordStatus.new(messages_seen: seen)
      end

      def start_handler
        Worker.new "RecordSpanHandler" do
          begin
            @record_spans.each do |span|
              @server.notice_span span
              if seen >= @next_seen_hurdle
                @next_seen_hurdle += HURDLE_INCREMENT
                @record_status_stream.push(record_status)
              end
            end
            @record_status_stream.push(record_status)
            @record_status_stream.push(nil)
          rescue StandardError => e
            puts "SERVER ERROR", e.inspect
            raise e
          ensure
            @lock.synchronize { @worker, @record_spans = nil }
          end
        end
      end

      def flush
        return unless @worker
        @worker.join while @lock.synchronize { @record_spans }
      end

      def stop
        return unless @worker
        @lock.synchronize do
          @worker.stop
          @worker = nil
        end
      end
    end

    class OkCloseSpanHandler < RecordSpanHandler
      def start_handler
        Worker.new "RecordSpanHandler" do
          begin
            @record_spans.each do |span|
              @server.notice_span span
              if seen >= @next_seen_hurdle
                @next_seen_hurdle += HURDLE_INCREMENT
                @record_status_stream.push(record_status)
              end
            end
            @record_status_stream.push(record_status)
            @record_status_stream.push(nil)
          rescue ::GRPC::Ok => e 
            retry
          rescue StandardError => e
            puts "SERVER ERROR", e.inspect
            raise e
          ensure
            @lock.synchronize { @worker, @record_spans = nil }
          end
        end
      end
    end
  end
end