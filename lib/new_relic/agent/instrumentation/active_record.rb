# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_prepend'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecord
        EXPLAINER = lambda do |statement|
          connection = NewRelic::Agent::Database.get_connection(statement.config) do
            ::ActiveRecord::Base.send("#{statement.config[:adapter]}_connection",
                                      statement.config)
          end
          if connection && connection.respond_to?(:execute)
            return connection.execute("EXPLAIN #{statement.sql}")
          end
        end

        def self.insert_instrumentation
          if defined?(::ActiveRecord::VERSION::MAJOR) && ::ActiveRecord::VERSION::MAJOR.to_i >= 3
            if ::NewRelic::Agent.config[:prepend_active_record_instrumentation]
              ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions
              ::ActiveRecord::Relation.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::RelationExtensions
            else
              ::NewRelic::Agent::Instrumentation::ActiveRecordHelper.instrument_additional_methods
            end
          end

          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.module_eval do
            include ::NewRelic::Agent::Instrumentation::ActiveRecord
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

          product, operation, collection = ActiveRecordHelper.product_operation_collection_for(
            NewRelic::Helper.correctly_encoded(name),
            NewRelic::Helper.correctly_encoded(sql),
            @config && @config[:adapter])

          host = nil
          port_path_or_id = nil
          database = nil

          if ActiveRecordHelper::InstanceIdentification.supported_adapter?(@config)
            host = ActiveRecordHelper::InstanceIdentification.host(@config)
            port_path_or_id = ActiveRecordHelper::InstanceIdentification.port_path_or_id(@config)
            database = @config && @config[:database]
          end

          segment = NewRelic::Agent::Transaction.start_datastore_segment(
            product: product,
            operation: operation,
            collection: collection,
            host: host,
            port_path_or_id: port_path_or_id,
            database_name: database
          )
          segment._notice_sql(sql, @config, EXPLAINER)

          begin
            log_without_newrelic_instrumentation(*args, &block)
          ensure
            segment.finish if segment
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

    if defined?(::Rails::VERSION::MAJOR) && ::Rails::VERSION::MAJOR.to_i == 3
      ActiveSupport.on_load(:active_record) do
        ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
      end
    else
      ::NewRelic::Agent::Instrumentation::ActiveRecord.insert_instrumentation
    end
  end
end
