# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        module_function

        def metric_for_name(name)
          return unless name
          parts = name.split(' ')
          if parts.size == 2
            model = parts.first
            operation = parts.last.downcase
            case operation
            when 'load', 'count', 'exists'
              op_name = 'find'
            when 'indexes', 'columns'
              op_name = nil # fall back to DirectSQL
            when 'destroy', 'find', 'save', 'create'
              op_name = operation
            when 'update'
              op_name = 'save'
            else
              if model == 'Join'
                op_name = operation
              end
            end
            "ActiveRecord/#{model}/#{op_name}" if op_name
          end
        end

        def metric_for_sql(sql)
          metric = NewRelic::Agent::Transaction.database_metric_name
          if metric.nil?
            if sql =~ /^(select|update|insert|delete|show)/i
              # Could not determine the model/operation so let's find a better
              # metric.  If it doesn't match the regex, it's probably a show
              # command or some DDL which we'll ignore.
              metric = "Database/SQL/#{$1.downcase}"
            else
              metric = "Database/SQL/other"
            end
          end
          metric
        end

        # Given a metric name such as "ActiveRecord/model/action" this
        # returns an array of rollup metrics:
        # [ "ActiveRecord/all", "ActiveRecord/action" ]
        # If the metric name is in the form of "ActiveRecord/action"
        # this returns merely: [ "ActiveRecord/all" ]
        def rollup_metrics_for(metric)
          metrics = []

          # If we're outside of a web transaction, don't record any rollup
          # database metrics. This is to prevent metrics from background tasks
          # from polluting the metrics used to drive overview graphs.
          if NewRelic::Agent::Transaction.recording_web_transaction?
            metrics << "ActiveRecord/all"
          end
          metrics << "ActiveRecord/#{$1}" if metric =~ /ActiveRecord\/[\w|\:]+\/(\w+)/

          metrics
        end

        # Given a database adapter name and a database server host
        # this returns a metric name in the form:
        # "RemoteService/sql/adapter/host"
        # Host defaults to "localhost".
        def remote_service_metric(adapter, host)
          host ||= 'localhost'
          type = adapter.to_s.sub(/\d*/, '')
          "RemoteService/sql/#{type}/#{host}"
        end
      end
    end
  end
end
