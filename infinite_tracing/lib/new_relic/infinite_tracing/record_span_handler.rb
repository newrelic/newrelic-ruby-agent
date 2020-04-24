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
        @mutex = Mutex.new
        @mutex.synchronize { @worker = start_handler }
      end

      def seen
        @server.seen
      end

      def enumerator
        @record_status_stream.each_item
      end

      def record_status
        puts "#{@id}: RECORDS SEEN: #{seen}" unless quiet?
        Com::Newrelic::Trace::V1::RecordStatus.new(messages_seen: seen)
      end

      def start_handler
        puts "#{@id}: RECORDING SPANS!"
        Worker.new "RecordSpanHandler[#{@id}]" do
          begin
            @record_spans.each do |span|
              @server.notice_span span
              puts "#{@id}: receiving #{seen}"
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
            @mutex.synchronize { @worker, @record_spans = nil }
          end
        end
      end

      def flush
        return unless @worker
        @worker.join while @mutex.synchronize { @record_spans }
      end

      def stop
        return unless @worker
        @mutex.synchronize do
          puts "#{@id}: Stopping Record Span Handler"
          @worker.stop
          @worker = nil
        end
      end
    end

  end
end