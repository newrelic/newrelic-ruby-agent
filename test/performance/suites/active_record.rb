# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


class ActiveRecordTest < Performance::TestCase
  def setup
    require 'new_relic/agent/instrumentation/active_record_helper'

    ActiveRecordTest.const_set(:ActiveRecordHelper, NewRelic::Agent::Instrumentation::ActiveRecordHelper) unless defined?(ActiveRecordHelper)

    if ActiveRecordHelper.respond_to?(:metrics_for)
      @run = ActiveRecordHelper.method(:metrics_for)
    else
      # Mimics what was buried in the instrumentation that we replaced with
      # calls to metrics_for in the new instrumentation. Can run against SHA
      # 399d8ed for baselining (3.10 tags won't work since the perf testing
      # changed on dev post 3.10)
      @run = proc do |name, sql, adapter, *_|
        metric = ActiveRecordHelper.metric_for_name(name) ||
                 ActiveRecordHelper.metric_for_sql(sql)
        remote_service_metric = ActiveRecordHelper.remote_service_metric("host", adapter)

        metrics = [metric, remote_service_metric].compact
        metrics += ActiveRecordHelper.rollup_metrics_for(metric)
      end
    end
  end

  NAME    = "Model Load"
  SQL     = "SELECT * FROM star"
  ADAPTER = "mysql2"

  def test_helper_by_name
    measure do
      @run.call(NAME, SQL, ADAPTER)
    end
  end

  UNKNOWN_NAME = "Blah"

  def test_helper_by_sql
    measure do
      @run.call(UNKNOWN_NAME, SQL, ADAPTER)
    end
  end
end
