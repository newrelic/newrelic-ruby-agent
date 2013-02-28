# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecord2
        include NewRelic::Agent::Instrumentation

        def self.included(instrumented_class)
          instrumented_class.class_eval do
            unless instrumented_class.method_defined?(:log_without_newrelic_instrumentation)
              alias_method :log_without_newrelic_instrumentation, :log
              alias_method :log, :log_with_newrelic_instrumentation
              protected :log
            end
          end
        end

        def log_with_newrelic_instrumentation(*args, &block)
          if !NewRelic::Agent.is_execution_traced?
            return log_without_newrelic_instrumentation(*args, &block)
          end

          sql, name, binds = args
          metric = ActiveRecordHelper.metric_for_name(NewRelic::Helper.correctly_encoded(name)) ||
            ActiveRecordHelper.metric_for_sql(NewRelic::Helper.correctly_encoded(sql))

          if !metric
            log_without_newrelic_instrumentation(*args, &block)
          else
            metrics = [ metric ]
            if @config
              metrics << ActiveRecordHelper.remote_service_metric(@config[:adapter], @config[:host])
            end
            metrics += ActiveRecordHelper.rollup_metrics_for(metric)
            self.class.trace_execution_scoped(metrics) do
              t0 = Time.now
              begin
                log_without_newrelic_instrumentation(*args, &block)
              ensure
                elapsed_time = (Time.now - t0).to_f
                NewRelic::Agent.instance.transaction_sampler.notice_sql(sql,
                                                         @config, elapsed_time)
                NewRelic::Agent.instance.sql_sampler.notice_sql(sql, metric,
                                                         @config, elapsed_time)
              end
            end
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :active_record_2

  depends_on do
    defined?(ActiveRecord) && defined?(ActiveRecord::Base) &&
      ::ActiveRecord::VERSION::MAJOR.to_i <= 2
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing ActiveRecord 2 instrumentation'
  end

  executes do
    insert_instrumentation
  end

  def insert_instrumentation
    ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
      include ::NewRelic::Agent::Instrumentation::ActiveRecord2
    end

    ActiveRecord::Base.class_eval do
      class << self
        add_method_tracer(:find_by_sql, 'ActiveRecord/#{self.name}/find_by_sql',
                          :metric => false)
        add_method_tracer(:transaction, 'ActiveRecord/#{self.name}/transaction',
                          :metric => false)
      end
    end
  end
end
