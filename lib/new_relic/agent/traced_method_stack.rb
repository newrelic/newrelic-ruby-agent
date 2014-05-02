# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TracedMethodFrame
      attr_reader :deduct_call_time_from_parent, :tag
      attr_accessor :name, :start_time, :children_time, :type
      def initialize(tag, start_time, deduct_call_time)
        @tag = tag
        @start_time = start_time
        @deduct_call_time_from_parent = deduct_call_time
        @children_time = 0
      end
    end

    # TracedMethodStack is responsible for tracking the push and pop of methods
    # that we are tracing, notifying the transaction sampler, and calculating
    # exclusive time when a method is complete. This is allowed whether a
    # transaction is in progress not.
    class TracedMethodStack
      def initialize
        @stack = []
      end

      def self.push_frame(tag, time = Time.now.to_f, deduct_call_time_from_parent = true)
        stack = NewRelic::Agent::TransactionState.get.traced_method_stack
        stack.push_frame(tag, time, deduct_call_time_from_parent)
      end

      def self.pop_frame(expected_frame, name, time=Time.now.to_f)
        stack = NewRelic::Agent::TransactionState.get.traced_method_stack
        stack.pop_frame(expected_frame, name, time)
      end

      # Pushes a frame onto the transaction stack - this generates a
      # TransactionSample::Segment at the end of transaction execution.
      #
      # The generated segment won't be named until pop_frame is called.
      #
      # +tag+ should be a Symbol, and is only for debugging purposes to
      # identify this frame if the stack gets corrupted.
      def push_frame(tag, time = Time.now.to_f, deduct_call_time_from_parent = true)
        transaction_sampler.notice_push_frame(time) if sampler_enabled?
        frame = TracedMethodFrame.new(tag, time, deduct_call_time_from_parent)
        @stack.push frame
        frame
      end

      # Pops a frame off the transaction stack - this updates the transaction
      # sampler that we've finished execution of a traced method.
      #
      # +expected_frame+ should be TracedMethodFrame from the corresponding
      # push_frame call.
      #
      # +name+ will be applied to the generated transaction trace segment.
      def pop_frame(expected_frame, name, time=Time.now.to_f)
        frame = @stack.pop
        fail "unbalanced pop from blame stack, got #{frame ? frame.tag : 'nil'}, expected #{expected_frame ? expected_frame.tag : 'nil'}" if frame != expected_frame

        if !@stack.empty?
          if frame.deduct_call_time_from_parent
            @stack.last.children_time += (time - frame.start_time)
          else
            @stack.last.children_time += frame.children_time
          end
        end
        transaction_sampler.notice_pop_frame(name, time) if sampler_enabled?
        frame.name = name
        frame
      end

      def sampler_enabled?
        Agent.config[:'transaction_tracer.enabled'] || Agent.config[:developer_mode]
      end

      def transaction_sampler
        Agent.instance.transaction_sampler
      end

      def empty?
        @stack.empty?
      end
    end
  end
end
