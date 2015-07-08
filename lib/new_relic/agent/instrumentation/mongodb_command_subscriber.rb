# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
module NewRelic
  module Agent
    module Instrumentation
      class MongodbCommandSubscriber

        MONGODB = 'MongoDB'.freeze

        def started(event)
          begin
            return unless NewRelic::Agent.tl_is_execution_traced?
            operations[event.operation_id] = event
          rescue Exception => e
            log_notification_error('started', e)
          end
        end

        def completed(event)
          begin
            state = NewRelic::Agent::TransactionState.tl_get
            return unless state.is_execution_traced?
            started_event = operations.delete(event.operation_id)

            base, *other_metrics = metrics(started_event)

            NewRelic::Agent.instance.stats_engine.tl_record_scoped_and_unscoped_metrics(
              base, other_metrics, event.duration
            )

            NewRelic::Agent.instance.transaction_sampler.notice_nosql_statement(
              format_statement(started_event), event.duration
            )
          rescue Exception => e
            log_notification_error('completed', e)
          end
        end

        alias :succeeded :completed
        alias :failed :completed

        private

        def collection(event)
          event.command.values.first
        end

        def metrics(event)
          NewRelic::Agent::Datastores::MetricHelper.metrics_for(MONGODB, event.command_name, collection(event))
        end

        def log_notification_error(event_type, error)
          NewRelic::Agent.logger.error("Error during MongoDB #{event_type} event:")
          NewRelic::Agent.logger.log_exception(:error, error)
        end

        def operations
          @operations ||= {}
        end

        def format_statement(event)
          "#{event.database_name}.#{event.command_name} #{event.command}"
        end
      end
    end
  end
end
