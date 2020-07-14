# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

module NewRelic::Agent::InfiniteTracing
  class RecordStatusHandlerTest < Minitest::Test

    def process_queue handler, queue
      Thread.pass until queue.empty?
      handler.stop
    end

    def test_processes_single_item_and_stops
      queue = EnumeratorQueue.new.preload(RecordStatus.new(messages_seen: 12))

      handler = build_handler queue
      process_queue handler, queue

      assert_equal 12, handler.messages_seen
    end

    def test_processes_multiple_items_and_stops
      items = 5.times.map{|i| RecordStatus.new(messages_seen: i + 1)}
      queue = EnumeratorQueue.new.preload(items)

      handler = build_handler queue
      process_queue handler, queue

      assert_equal 5, handler.messages_seen
    end

    def test_processes_error_on_queue
      error_object = RuntimeError.new("oops")
      queue = EnumeratorQueue.new.preload(error_object)

      handler = build_handler queue
      process_queue handler, queue

      assert_equal 0, handler.messages_seen
    end

    def test_processes_nil_on_queue
      queue = EnumeratorQueue.new

      handler = build_handler queue
      process_queue handler, queue

      assert_equal 0, handler.messages_seen
    end

    private 

    class TestClient
      def handle_error error
        NewRelic::Agent.record_metric "Supportability/InfiniteTracing/Span/Response/Error", 0.0
      end
    end

    def build_handler queue
      RecordStatusHandler.new TestClient.new, queue.each_item
    end

  end
end
