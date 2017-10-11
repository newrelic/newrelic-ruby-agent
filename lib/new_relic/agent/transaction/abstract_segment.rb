# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class AbstractSegment
        attr_reader :start_time, :end_time, :duration, :exclusive_duration
        attr_accessor :name, :parent, :children_time, :transaction
        attr_writer :record_metrics, :record_scoped_metric, :record_on_finish

        def initialize name=nil, start_time=nil
          @name = name
          @children_time = 0.0
          @running_children = 0
          @concurrent_children = false
          @record_metrics = true
          @record_scoped_metric = true
          @transaction = nil
          @parent = nil
          @record_on_finish = false
          @params = nil
          @start_time = start_time if start_time
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

          parent.children_time += duration if parent
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

        def before_finalize
          unless finished?
            finish
            NewRelic::Agent.logger.warn "Segment: #{name} was unfinished at " \
              "the end of transaction. Timing information for " \
              "#{transaction.best_name} may be inaccurate."
          end
        end

        def finalize
          @exclusive_duration = duration - children_time
          record_metrics if record_metrics?
        end

        def params
          @params ||= {}
        end

        def params?
          !!@params
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
        end

        private

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
