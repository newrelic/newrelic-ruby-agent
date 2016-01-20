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
          if defined?(::ActiveRecord::VERSION::MAJOR) && ::ActiveRecord::VERSION::MAJOR.to_i >= 3
            ::NewRelic::Agent::Instrumentation::ActiveRecordHelper.instrument_additional_methods
          end

          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::NewRelic::Agent::Instrumentation::ActiveRecord
          end
        end

        def self.included(instrumented_class)
          instrumented_class.class_eval do
            protected :log
            unless include?(NewRelic::Agent::Instrumentation::ActiveRecord::LogInstrumentation)
              prepend NewRelic::Agent::Instrumentation::ActiveRecord::LogInstrumentation
            end
          end
        end

        module LogInstrumentation
          protected
          def log(*args, &block) #THREAD_LOCAL_ACCESS
            state = NewRelic::Agent::TransactionState.tl_get

            if !state.is_execution_traced?
              return super(*args, &block)
            end

            sql, name, _ = args
            metrics = ActiveRecordHelper.metrics_for(
              NewRelic::Helper.correctly_encoded(name),
              NewRelic::Helper.correctly_encoded(sql),
              @config && @config[:adapter])

            # It is critical that we grab this name before trace_execution_scoped
            # because that method mutates the metrics list passed in.
            scoped_metric = metrics.first

            NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
              t0 = Time.now
              begin
                super(*args, &block)
              ensure
                elapsed_time = (Time.now - t0).to_f

                NewRelic::Agent.instance.transaction_sampler.notice_sql(sql,
                                                      @config, elapsed_time,
                                                      state, EXPLAINER)
                NewRelic::Agent.instance.sql_sampler.notice_sql(sql, scoped_metric,
                                                      @config, elapsed_time,
                                                      state, EXPLAINER)
              end
            end
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
    require 'new_relic/agent/instrumentation/active_record_helper'

    if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3
      ActiveSupport.on_load(:active_record) do
        ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
      end
    else
      ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
    end
  end
end
