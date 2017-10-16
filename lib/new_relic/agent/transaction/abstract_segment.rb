# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/range_extensions'

module NewRelic
  module Agent
    class Transaction
      class AbstractSegment
        attr_reader :start_time, :end_time, :duration, :exclusive_duration
        attr_accessor :name, :parent, :children_time, :transaction
        attr_writer :record_metrics, :record_scoped_metric, :record_on_finish

        def initialize name=nil, start_time=nil
          @name = name
          @transaction = nil
          @parent = nil
          @params = nil
          @start_time = start_time if start_time
          @end_time = nil
          @duration = 0.0
          @exclusive_duration = 0.0
          @children_time = 0.0
          @children_time_ranges = nil
          @running_children = 0
          @concurrent_children = false
          @record_metrics = true
          @record_scoped_metric = true
          @record_on_finish = false
        end

        def start
          @start_time ||= Time.now
          return unless transaction
          parent.child_start self if parent
        end

        def finish
          @end_time = Time.now
          @duration = end_time.to_f - start_time.to_f
          return unless transaction
          run_complete_callbacks
          finalize if record_on_finish?
        rescue => e
          NewRelic::Agent.logger.error "Exception finishing segment: #{name}", e
        end

        def finished?
          !!@end_time
        end

        def record_metrics?
          @record_metrics
        end

        def record_scoped_metric?
          @record_scoped_metric
        end

        def record_on_finish?
          @record_on_finish
        end

        def finalize
          force_finish unless finished?
          calculate_exclusive_duration
          record_metrics if record_metrics?
        end

        def params
          @params ||= {}
        end

        def params?
          !!@params
        end

        def children_time_ranges
          @children_time_ranges ||= []
        end

        def children_time_ranges?
          !!@children_time_ranges
        end

        def concurrent_children?
          @concurrent_children
        end

        INSPECT_IGNORE = [:@transaction, :@transaction_state].freeze

        def inspect
          ivars = (instance_variables - INSPECT_IGNORE).inject([]) do |memo, var_name|
            memo << "#{var_name}=#{instance_variable_get(var_name).inspect}"
          end
          sprintf('#<%s:0x%x %s>', self.class.name, object_id, ivars.join(', '))
        end

        protected

        def child_start segment
          @running_children += 1
          @concurrent_children = @concurrent_children || @running_children > 1
        end

        def child_complete segment
          @running_children -= 1
          record_child_time segment
        end

        private

        def force_finish
          finish
          NewRelic::Agent.logger.warn "Segment: #{name} was unfinished at " \
            "the end of transaction. Timing information for this segment's" \
            "parent #{parent.name} in #{transaction.best_name} may be inaccurate."
        end

        def run_complete_callbacks
          segment_complete
          parent.child_complete self if parent
          transaction.segment_complete self
        end

        def record_metrics
          raise NotImplementedError, "Subclasses must implement record_metrics"
        end

        # callback for subclasses to override
        def segment_complete
          raise NotImplementedError
        end

        def record_child_time child
          if concurrent_children? || finished? && end_time < child.end_time
            RangeExtensions.merge_or_append child.start_time..child.end_time,
                                            children_time_ranges
          else
            self.children_time += child.duration
          end
        end

        def calculate_exclusive_duration
          overlapping_duration = if children_time_ranges?
            RangeExtensions.compute_overlap start_time..end_time, children_time_ranges
          else
            0.0
          end
          @exclusive_duration = duration - children_time - overlapping_duration
        end

        def metric_cache
          transaction.metrics
        end

        def transaction_state
          @transaction_state ||= if @transaction
            transaction.state
          else
            TransactionState.tl_get
          end
        end
      end
    end
  end
end
