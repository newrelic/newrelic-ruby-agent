# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/prepend_supportability'
require 'new_relic/agent/instrumentation/active_record_helper'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordPrepend
        ACTIVE_RECORD = 'ActiveRecord'.freeze

        module BaseExtensions
          if NewRelic::Helper.version_satisfied?(RUBY_VERSION, '<', '2.7.0')
            def save(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end

            def save!(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end

          else
            def save(*args, **kwargs, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end

            def save!(*args, **kwargs, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end

          end

          private

          def newrelic_model_collection_name
            NewRelic::Agent::Instrumentation::ActiveRecordHelper.use_table_name? ? self.class.table_name : self.class.name
          end
        end

        module BaseExtensions516
          # In ActiveRecord v5.0.0 through v5.1.5, touch() will call
          # update_all() and cause us to record a transaction.
          # Starting in v5.1.6, this call no longer happens. We'll
          # have to set the database metrics explicitly now.
          #
          if NewRelic::Helper.version_satisfied?(RUBY_VERSION, '<', '2.7.0')
            def touch(*args, **kwargs, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end
          else
            def touch(*args, **kwargs, &blk)
              ::NewRelic::Agent.with_database_metric_name(newrelic_model_collection_name, nil, ACTIVE_RECORD) do
                super
              end
            end
          end

          private

          def newrelic_model_collection_name
            NewRelic::Agent::Instrumentation::ActiveRecordHelper.use_table_name? ? self.class.table_name : self.class.name
          end
        end

        module RelationExtensions
          def update_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(newrelic_relation_collection_name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def delete_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(newrelic_relation_collection_name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def destroy_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(newrelic_relation_collection_name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def calculate(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(newrelic_relation_collection_name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def pluck(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(newrelic_relation_collection_name, nil, ACTIVE_RECORD) do
              super
            end
          end

          private

          def newrelic_relation_collection_name
            NewRelic::Agent::Instrumentation::ActiveRecordHelper.use_table_name? ? self.klass.table_name : self.name
          end
        end
      end
    end
  end
end
