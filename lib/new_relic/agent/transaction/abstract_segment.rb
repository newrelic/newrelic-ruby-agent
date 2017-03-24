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

        def initialize name=nil
          @name = name
          @children_time = 0.0
          @record_metrics = true
          @record_scoped_metric = true
          @transaction = nil
          @parent = nil
          @record_on_finish = false
        end

        def start
          @start_time = Time.now
        end

        def finish
          @end_time = Time.now
          @duration = end_time.to_f - start_time.to_f
          @exclusive_duration = duration - children_time
          if transaction
            record_metrics if record_metrics? && record_on_finish?
            segment_complete
            parent.child_complete self if parent
            transaction.segment_complete self
          end
        rescue => e
          # This rescue block was added for the benefit of this test:
          # test/multiverse/suites/bare/standalone_instrumentation_test.rb
          # See the top of the test for details.
          NewRelic::Agent.logger.error "Exception finishing segment: #{name}", e
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

        def record_metrics
          raise NotImplementedError, "Subclasses must implement record_metrics"
        end

        INSPECT_IGNORE = [:@transaction, :@transaction_state].freeze

        def inspect
          ivars = (instance_variables - INSPECT_IGNORE).inject([]) do |memo, var_name|
            memo << "#{var_name}=#{instance_variable_get(var_name).inspect}"
          end
          sprintf('#<%s:0x%x %s>', self.class.name, object_id, ivars.join(', '))
        end

        protected

        def child_complete segment
          if segment.record_metrics?
            self.children_time += segment.duration
          else
            self.children_time += segment.children_time
          end
        end

        private

        # callback for subclasses to override
        def segment_complete
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
