# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/prepend_supportability'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordPrepend
        ACTIVE_RECORD = 'ActiveRecord'.freeze

        module BaseExtensions
          def save(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.class.name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def save!(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.class.name, nil, ACTIVE_RECORD) do
              super
            end
          end
        end

        module RelationExtensions
          def update_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def delete_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def destroy_all(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def calculate(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
              super
            end
          end

          def pluck(*args, &blk)
            ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
              super
            end
          end
        end
      end
    end
  end
end
