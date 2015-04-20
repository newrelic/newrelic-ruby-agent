# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TracedMethodFrame
      attr_reader :tag
      attr_accessor :name, :start_time, :children_time
      def initialize(tag, start_time)
        @tag = tag
        @start_time = start_time
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

      # Pushes a frame onto the transaction stack - this generates a
      # Agent::Transaction::TraceNode at the end of transaction execution.
      #
      # The generated node won't be named until pop_frame is called.
      #
      # +tag+ should be a Symbol, and is only for debugging purposes to
      # identify this frame if the stack gets corrupted.
      def push_frame(state, tag, time = Time.now.to_f)
        transaction_sampler.notice_push_frame(state, time) if sampler_enabled?
        frame = TracedMethodFrame.new(tag, time)
        @stack.push frame
        frame
      end

      # Pops a frame off the transaction stack - this updates the transaction
      # sampler that we've finished execution of a traced method.
      #
      # +expected_frame+ should be TracedMethodFrame from the corresponding
      # push_frame call.
      #
      # +name+ will be applied to the generated transaction trace node.
      def pop_frame(state, expected_frame, name, time, deduct_call_time_from_parent=true)
        frame = fetch_matching_frame(expected_frame)

        note_children_time(frame, time, deduct_call_time_from_parent)

        transaction_sampler.notice_pop_frame(state, name, time) if sampler_enabled?
        frame.name = name
        frame
      end

      def fetch_matching_frame(expected_frame)
        while frame = @stack.pop
          if frame == expected_frame
            return frame
          else
            NewRelic::Agent.logger.info("Unexpected frame in traced method stack: #{frame.inspect} expected to be #{expected_frame.inspect}")
            NewRelic::Agent.logger.debug do
              ["Backtrace for unexpected frame: ", caller.join("\n")]
            end
          end
        end

        raise "Frame not found in blame stack: #{expected_frame.inspect}"
      end

      def note_children_time(frame, time, deduct_call_time_from_parent)
        if !@stack.empty?
          if deduct_call_time_from_parent
            @stack.last.children_time += (time - frame.start_time)
          else
            @stack.last.children_time += frame.children_time
          end
        end
      end

      def sampler_enabled?
        Agent.config[:'transaction_tracer.enabled'] || Agent.config[:developer_mode]
      end

      def transaction_sampler
        Agent.instance.transaction_sampler
      end

      def clear
        @stack.clear
      end

      def empty?
        @stack.empty?
      end
    end
  end
end
