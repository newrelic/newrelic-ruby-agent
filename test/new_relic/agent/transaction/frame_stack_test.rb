# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/transaction/frame_stack'

class NewRelic::Agent::Transaction
  class FrameStackTest < Minitest::Test
    def setup
      @stack = FrameStack.new
    end

    def test_an_initialized_frame_stack_is_empty
      assert @stack.empty?
    end

    def test_push_appends_item
      item = Object.new
      @stack.push item
      assert_equal item, @stack.last
    end

    def test_pop_removes_and_returns_an_item
      item = Object.new
      @stack.push item
      popped = @stack.pop
      assert_equal item, popped
    end

    def test_last_returns_top_of_stack
      item1, item2 = Object.new, Object.new
      @stack.push item1
      @stack.push item2
      assert_equal item2, @stack.last
    end

    def test_max_depth_multi_push
      3.times { @stack.push Object.new }
      assert_equal 3, @stack.max_depth
    end

    def test_max_depth_remembers_deepest_depth
      3.times { @stack.push Object.new }
      3.times { @stack.pop }
      assert_equal 3, @stack.max_depth
    end
  end
end
