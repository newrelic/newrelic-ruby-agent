# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_subscriber'
require 'new_relic/agent/instrumentation/active_record_prepend'


# Provides a way to send :connection through ActiveSupport notifications to avoid
# looping through connection handlers to locate a connection by connection_id
# This is not needed in Rails 6+: https://github.com/rails/rails/pull/34602
module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordNotifications
        module BaseExtensions41
          def self.included(base)
            base.class_eval do
              alias_method :log_without_performance_improvement, :log
              alias_method :log, :log_with_performance_improvement
            end
          end

          # https://github.com/rails/rails/blob/4-1-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L371
          def log_with_performance_improvement(sql, name = "SQL", binds = [], statement_name = nil)
            @instrumenter.instrument(
              "sql.active_record",
              :sql            => sql,
              :name           => name,
              :connection_id  => object_id,
              :connection     => self,
              :statement_name => statement_name,
              :binds          => binds) { yield }
          rescue => e
            raise translate_exception(e, sql)
          end
        end

        module BaseExtensions50
          def self.included(base)
            base.class_eval do
              alias_method :log_without_performance_improvement, :log
              alias_method :log, :log_with_performance_improvement
            end
          end

          # https://github.com/rails/rails/blob/5-0-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L582
          def log_with_performance_improvement(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = nil)
            @instrumenter.instrument(
              "sql.active_record",
              sql:               sql,
              name:              name,
              binds:             binds,
              type_casted_binds: type_casted_binds,
              statement_name:    statement_name,
              connection_id:     object_id,
              connection:        self) { yield }
          rescue => e
            raise translate_exception_class(e, sql)
          end
        end

        module BaseExtensions51
          def self.included(base)
            base.class_eval do
              alias_method :log_without_performance_improvement, :log
              alias_method :log, :log_with_performance_improvement
            end
          end

          # https://github.com/rails/rails/blob/5-1-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L603
          def log_with_performance_improvement(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = nil) # :doc:
            @instrumenter.instrument(
              "sql.active_record",
              sql:               sql,
              name:              name,
              binds:             binds,
              type_casted_binds: type_casted_binds,
              statement_name:    statement_name,
              connection_id:     object_id,
              connection:        self) do
                @lock.synchronize do
                  yield
                end
              end
          rescue => e
            raise translate_exception_class(e, sql)
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  named :active_record_notifications

  depends_on do
    defined?(::ActiveRecord) && defined?(::ActiveRecord::Base) &&
      defined?(::ActiveRecord::VERSION) &&
      ::ActiveRecord::VERSION::MAJOR.to_i >= 4
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.subscribed?
  end


  depends_on do
    # If the deprecated :disable_active_record_4 setting is true, and
    # the active record version is four, disable!
    NewRelic::Agent.config[:disable_active_record_4] == false \
        || ::ActiveRecord::VERSION::MAJOR.to_i != 4
  end

  depends_on do
    # If the deprecated :disable_active_record_5 setting is true, and
    # the active record version is five, disable!
    NewRelic::Agent.config[:disable_active_record_5] == false \
        || ::ActiveRecord::VERSION::MAJOR.to_i  != 5
  end


  executes do
    ::NewRelic::Agent.logger.info 'Installing notifications based Active Record instrumentation'
  end

  executes do
    ActiveSupport::Notifications.subscribe('sql.active_record',
      NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new)
  end

  executes do
    ActiveSupport.on_load(:active_record) do
      ::NewRelic::Agent::PrependSupportability.record_metrics_for(
          ::ActiveRecord::Base,
          ::ActiveRecord::Relation)

      # Default to .prepending, unless the ActiveRecord version is <=4
      # **AND** the :prepend_active_record_instrumentation config is false
      if ::ActiveRecord::VERSION::MAJOR > 4 \
          || ::NewRelic::Agent.config[:prepend_active_record_instrumentation]

        ::ActiveRecord::Base.send(:prepend,
            ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions)
        ::ActiveRecord::Relation.send(:prepend,
            ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::RelationExtensions)
      else
        ::NewRelic::Agent::Instrumentation::ActiveRecordHelper.instrument_additional_methods
      end
    end
  end

  executes do
    if NewRelic::Agent.config[:backport_fast_active_record_connection_lookup]

      activerecord_extension = if ::ActiveRecord::VERSION::MAJOR.to_i == 4
        ::NewRelic::Agent::Instrumentation::ActiveRecordNotifications::BaseExtensions41
      elsif ::ActiveRecord::VERSION::MAJOR.to_i == 5
        if ::ActiveRecord::VERSION::MINOR.to_i == 0
          ::NewRelic::Agent::Instrumentation::ActiveRecordNotifications::BaseExtensions50
        elsif ::ActiveRecord::VERSION::MINOR.to_i >= 1
          ::NewRelic::Agent::Instrumentation::ActiveRecordNotifications::BaseExtensions51
        end
      end

      unless activerecord_extension.nil?
        ::ActiveRecord::ConnectionAdapters::AbstractAdapter.send(:include, activerecord_extension)
      end
    end
  end

  executes do
    if ::ActiveRecord::VERSION::MAJOR == 5 \
        && ::ActiveRecord::VERSION::MINOR.to_i == 1 \
        && ::ActiveRecord::VERSION::TINY.to_i >= 6

      ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions516
    end
  end
end
