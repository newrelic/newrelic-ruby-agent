# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/mongo_metric_translator'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::MongoMetricTranslatorTest < Test::Unit::TestCase
  def test_metrics_for_insert
    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:insert, { :collection => 'tribbles' })
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/insert",
      "Datastore/statement/MongoDB/tribbles/insert"
    ]

    assert_equal expected, metrics
  end

  def _test_metrics_for_find
  end

  def _test_metrics_for_find_one
  end

  def _test_metrics_for_remove
  end

  def _test_metrics_for_save
  end

  def _test_metrics_for_update
  end

  def _test_metrics_for_distinct
  end

  def _test_metrics_for_count
  end

  def _test_metrics_for_find_and_modify
  end

  def _test_metrics_for_find_and_remove
  end

  def _test_metrics_for_create_index
  end

  def _test_metrics_for_ensure_index
  end

  def _test_metrics_for_drop_index
  end

  def _test_metrics_for_drop_indexes
  end

  def _test_metrics_for_reindex
  end
end
