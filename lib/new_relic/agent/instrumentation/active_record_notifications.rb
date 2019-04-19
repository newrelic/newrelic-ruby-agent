# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_notifications'
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
          # https://github.com/rails/rails/blob/4-1-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L371
          def log(sql, name = "SQL", binds = [], statement_name = nil)
            @instrumenter.instrument(
              "sql.active_record",
              :sql            => sql,
              :name           => name,
              :connection_id  => object_id,
              :connection     => self,
              :statement_name => statement_name,
              :binds          => binds) { yield }
          rescue => e
            raise translate_exception_class(e, sql)
          end
        end

        module BaseExtensions50
          # https://github.com/rails/rails/blob/5-0-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L582
          def log(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = nil)
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
          # https://github.com/rails/rails/blob/5-1-stable/activerecord/lib/active_record/connection_adapters/abstract_adapter.rb#L603
          def log(sql, name = "SQL", binds = [], type_casted_binds = [], statement_name = nil) # :doc:
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
      ::ActiveRecord::VERSION::MAJOR.to_i >= 5
  end

  depends_on do
    !NewRelic::Agent.config[:disable_activerecord_instrumentation] &&
      !NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.subscribed?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing notifications based Active Record instrumentation'
  end

  executes do
    ActiveSupport::Notifications.subscribe('sql.active_record',
      NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new)

    ActiveSupport.on_load(:active_record) do
      ::NewRelic::Agent::PrependSupportability.record_metrics_for(::ActiveRecord::Base, ::ActiveRecord::Relation)
      ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions
      ::ActiveRecord::Relation.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::RelationExtensions

      if ::ActiveRecord::VERSION::MINOR.to_i == 1 &&
         ::ActiveRecord::VERSION::TINY.to_i >= 6
        ::ActiveRecord::Base.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordPrepend::BaseExtensions516
      end

      if NewRelic::Agent.config[:backport_fast_active_record_connection_lookup]
        if ::ActiveRecord::VERSION::MINOR.to_i == 0
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordNotifications::BaseExtensions50
        elsif ::ActiveRecord::VERSION::MINOR.to_i >= 1
          ::ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend ::NewRelic::Agent::Instrumentation::ActiveRecordNotifications::BaseExtensions51
        end
      end
    end
  end
end
