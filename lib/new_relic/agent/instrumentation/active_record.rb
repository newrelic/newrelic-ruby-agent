# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecord
        EXPLAINER = lambda do |config, query|
          connection = NewRelic::Agent::Database.get_connection(config) do
            ::ActiveRecord::Base.send("#{config[:adapter]}_connection",
                                      config)
          end
          if connection && connection.respond_to?(:execute)
            return connection.execute("EXPLAIN #{query}")
          end
        end

        def self.insert_instrumentation
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::NewRelic::Agent::Instrumentation::ActiveRecord
          end

          ::ActiveRecord::Base.class_eval do
            class << self
              add_method_tracer(:find_by_sql, 'ActiveRecord/#{self.name}/find_by_sql',
                                :metric => false)
              add_method_tracer(:transaction, 'ActiveRecord/#{self.name}/transaction',
                                :metric => false)
            end
          end
        end

        def self.included(instrumented_class)
          instrumented_class.class_eval do
            unless instrumented_class.method_defined?(:log_without_newrelic_instrumentation)
              alias_method :log_without_newrelic_instrumentation, :log
              alias_method :log, :log_with_newrelic_instrumentation
              protected :log
            end
          end
        end

        def log_with_newrelic_instrumentation(*args, &block) #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get

          if !state.is_execution_traced?
            return log_without_newrelic_instrumentation(*args, &block)
          end

          sql, name, _ = args
          metric = ActiveRecordHelper.metric_for_name(NewRelic::Helper.correctly_encoded(name)) ||
            ActiveRecordHelper.metric_for_sql(NewRelic::Helper.correctly_encoded(sql))

          if !metric
            log_without_newrelic_instrumentation(*args, &block)
          else
            metrics = [metric, remote_service_metric].compact
            metrics += ActiveRecordHelper.rollup_metrics_for(metric)
            self.class.trace_execution_scoped(metrics) do
              t0 = Time.now
              begin
                log_without_newrelic_instrumentation(*args, &block)
              ensure
                elapsed_time = (Time.now - t0).to_f

                NewRelic::Agent.instance.transaction_sampler.notice_sql(sql,
                                                      @config, elapsed_time,
                                                      state, &EXPLAINER)
                NewRelic::Agent.instance.sql_sampler.notice_sql(sql, metric,
                                                      @config, elapsed_time,
                                                      state, &EXPLAINER)
              end
            end
          end
        end

        def remote_service_metric
          if @config && @config[:adapter]
            ActiveRecordHelper.remote_service_metric(@config[:adapter], @config[:host])
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :active_record

  depends_on do
    defined?(::ActiveRecord) && defined?(::ActiveRecord::Base) &&
      (!defined?(::ActiveRecord::VERSION) ||
        ::ActiveRecord::VERSION::MAJOR.to_i <= 3)
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing ActiveRecord instrumentation'
  end

  executes do
    if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3
      ActiveSupport.on_load(:active_record) do
        ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
      end
    else
      ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
    end
  end
end
