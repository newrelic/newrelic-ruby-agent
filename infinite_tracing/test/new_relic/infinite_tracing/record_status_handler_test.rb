# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

class EnumeratorQueue
  extend Forwardable
  def_delegators :@queue, :push, :empty?

  def initialize items=nil
    @queue = Queue.new
    Array(items).each{ |item| @queue.push item }
  end

  def each_item
    return enum_for(:each_item) unless block_given?
    loop do
      value = @queue.pop
      break if value.nil?
      fail value if value.is_a? Exception
      yield value
    end
  end
end

module NewRelic
  module Agent
    module InfiniteTracing
      class RecordStatusHandlerTest < Minitest::Test

        def process_queue handler, queue
          Thread.pass until queue.empty?
          handler.stop
        end

        def test_processes_single_item_and_stops
          queue = EnumeratorQueue.new(RecordStatus.new(messages_seen: 12))

          handler = ResponseHandler.new queue.each_item
          process_queue handler, queue

          assert_equal 12, handler.messages_seen
        end

        def test_processes_multiple_items_and_stops
          items = 5.times.map{|i| RecordStatus.new(messages_seen: i + 1)}
          queue = EnumeratorQueue.new(items)

          handler = ResponseHandler.new queue.each_item
          process_queue handler, queue

          assert_equal 5, handler.messages_seen
        end

        def test_processes_error_on_queue
          error_object = RuntimeError.new("oops")
          queue = EnumeratorQueue.new(error_object)

          handler = ResponseHandler.new queue.each_item
          process_queue handler, queue

          assert_equal 0, handler.messages_seen
        end

        def test_processes_nil_on_queue
          queue = EnumeratorQueue.new([nil])

          handler = ResponseHandler.new queue.each_item
          process_queue handler, queue

          assert_equal 0, handler.messages_seen
        end

      end
    end
  end
end
