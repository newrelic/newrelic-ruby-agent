# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/collection_helper'
require 'new_relic/control'
require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/trace'

module NewRelic
  module Agent
    # a builder is created with every sampled transaction, to dynamically
    # generate the sampled data.  It is a thread-local object, and is not
    # accessed by any other thread so no need for synchronization.
    #
    # @api private
    class TransactionSampleBuilder

      # Once we hit the TT segment limit, we use this class to hold our place in
      # the tree so that we can still get accurate names and times on the
      # segments we've already created. The placeholder segment keeps a
      # depth counter that's incremented on each segment entry, and decremented
      # on exit, until it reaches zero, when we throw the placeholder away.
      # There should only ever be zero or one placeholder segment at a time.
      #
      # @api private
      class PlaceholderSegment
        attr_reader :parent_node
        attr_accessor :depth

        def initialize(parent_node)
          @parent_node = parent_node
          @depth = 1
        end

        # No-op - some clients expect to be able to use these to read/write
        # params on TT segments.
        def [](key); end
        def []=(key, value); end

        # Stubbed out in case clients try to touch params directly.
        def params; {}; end
        def params=; end
      end

      attr_reader :current_segment, :sample

      include NewRelic::CollectionHelper

      def initialize(time=Time.now)
        @sample = NewRelic::Agent::Transaction::Trace.new(time.to_f)
        @sample_start = time.to_f
        @current_segment = @sample.root_node
      end

      def sample_id
        @sample.sample_id
      end

      def segment_limit
        Agent.config[:'transaction_tracer.limit_segments']
      end

      def trace_entry(time)
        if @sample.count_nodes < segment_limit
          segment = @sample.create_segment(time.to_f - @sample_start)
          @current_segment.add_called_node(segment)
          @current_segment = segment
          if @sample.count_nodes == segment_limit()
            ::NewRelic::Agent.logger.debug("Segment limit of #{segment_limit} reached, ceasing collection.")
          end
        else
          if @current_segment.is_a?(PlaceholderSegment)
            @current_segment.depth += 1
          else
            @current_segment = PlaceholderSegment.new(@current_segment)
          end
        end
        @current_segment
      end

      def trace_exit(metric_name, time)
        if @current_segment.is_a?(PlaceholderSegment)
          @current_segment.depth -= 1
          if @current_segment.depth == 0
            @current_segment = @current_segment.parent_node
          end
        else
          @current_segment.metric_name = metric_name
          @current_segment.end_trace(time.to_f - @sample_start)
          @current_segment = @current_segment.parent_node
        end
      end

      def finish_trace(time=Time.now.to_f)
        # Should never get called twice, but in a rare case that we can't
        # reproduce in house it does.  log forensics and return gracefully
        if @sample.finished
          ::NewRelic::Agent.logger.error "Unexpected double-finish_trace of Transaction Trace Object: \n#{@sample.to_s}"
          return
        end
        @sample.root_node.end_trace(time.to_f - @sample_start)

        @sample.threshold = transaction_trace_threshold
        @sample.finished = true
        @current_segment = nil
      end

      TT_THRESHOLD_KEY = :'transaction_tracer.transaction_threshold'

      def transaction_trace_threshold #THREAD_LOCAL_ACCESS
        state = TransactionState.tl_get
        source_class = Agent.config.source(TT_THRESHOLD_KEY).class
        if source_class == Configuration::DefaultSource && state.current_transaction
          state.current_transaction.apdex_t * 4
        else
          Agent.config[TT_THRESHOLD_KEY]
        end
      end

      def scope_depth
        depth = -1        # have to account for the root
        current = @current_segment

        while(current)
          depth += 1
          current = current.parent_node
        end

        depth
      end

      def sample
        @sample
      end

    end
  end
end
