# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TransactionTraceNode
      attr_reader :deduct_call_time_from_parent, :tag
      attr_accessor :name, :start_time, :children_time
      def initialize(tag, start_time, deduct_call_time)
        @tag = tag
        @start_time = start_time
        @deduct_call_time_from_parent = deduct_call_time
        @children_time = 0
      end
    end

    class TransactionTraceNodeStack
      def initialize
        @stack = []
      end

      # Pushes a node onto the transaction stack - this generates a
      # TransactionSample::Segment at the end of transaction execution
      # The generated segment will not be named until the corresponding
      # pop_node call is made.
      # +tag+ should be a Symbol, and is only used for debugging purposes to
      # identify this node if the stack gets corrupted.
      def push_node(tag, time = Time.now.to_f, deduct_call_time_from_parent = true)
        transaction_sampler.notice_push_scope(time) if sampler_enabled?
        node = TransactionTraceNode.new(tag, time, deduct_call_time_from_parent)
        @stack.push node
        node
      end

      # Pops a node off the transaction stack - this updates the
      # transaction sampler that we've finished execution of a traced method
      # +expected_node+ should be the TransactionTraceNode that was returned by
      # the corresponding push_node call.
      # +name+ is the name that will be applied to the generated transaction
      # trace segment.
      def pop_node(expected_node, name, time=Time.now.to_f)
        node = @stack.pop
        fail "unbalanced pop from blame stack, got #{node ? node.tag : 'nil'}, expected #{expected_node ? expected_node.tag : 'nil'}" if node != expected_node

        if !@stack.empty?
          if node.deduct_call_time_from_parent
            @stack.last.children_time += (time - node.start_time)
          else
            @stack.last.children_time += node.children_time
          end
        end
        transaction_sampler.notice_pop_scope(name, time) if sampler_enabled?
        node.name = name
        node
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
