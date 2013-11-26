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

  def test_metrics_for_find
    payload = { :database   => "multiverse",
                :collection => "tribbles",
                :selector   => { "name" => "soterious johnson" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/find",
      "Datastore/statement/MongoDB/tribbles/find"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_find_one
    payload = { :database   => "multiverse",
                :collection => "tribbles",
                :selector   => {},
                :limit      => -1 }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/find_one",
      "Datastore/statement/MongoDB/tribbles/find_one"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_remove
    payload = { :database   => "multiverse",
                :collection => "tribbles",
                :selector   => { "name" => "soterious johnson" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:remove, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/remove",
      "Datastore/statement/MongoDB/tribbles/remove"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_update
    payload = { :database   => "multiverse",
                :collection => "tribbles",
                :selector   => { "name" => "soterious johnson" },
                :document   => { "name" => "codemonkey" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:update, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/update",
      "Datastore/statement/MongoDB/tribbles/update"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_distinct
    payload = { :database   => "multiverse",
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :distinct => "tribbles",
                                 :key      => "name",
                                 :query    => nil } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:distinct, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/distinct",
      "Datastore/statement/MongoDB/tribbles/distinct"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_count
    payload = { :database   => "multiverse",
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "count"  => "tribbles",
                                 "query"  => {},
                                 "fields" => nil } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/count",
      "Datastore/statement/MongoDB/tribbles/count"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_modify
    payload = { :database   => "multiverse",
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => "tribbles",
                                 :query         => { "name" => "soterious johnson" },
                                 :update        => {"name" => "codemonkey" } } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/find_and_modify",
      "Datastore/statement/MongoDB/tribbles/find_and_modify"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_remove
    payload = { :database   => "multiverse",
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => "tribbles",
                                 :query         => { "name" => "soterious johnson" },
                                 :remove        => true } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/find_and_remove",
      "Datastore/statement/MongoDB/tribbles/find_and_remove"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_create_index
    payload = { :database   => "multiverse",
                :collection => "system.indexes",
                :documents  => [ { :name => "name_1",
                                  :ns   => "multiverse.tribbles",
                                  :key  => { "name" => 1 } } ] }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:insert, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/create_index",
      "Datastore/statement/MongoDB/tribbles/create_index"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_indexes
    payload = { :database   => "multiverse",
                :collection => "$cmd",
                :limit      => -1,
                :selector => { :deleteIndexes => "tribbles",
                               :index         => "*" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/drop_indexes",
      "Datastore/statement/MongoDB/tribbles/drop_indexes"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_index
    payload = { :database => "multiverse",
                :collection => "$cmd",
                :limit => -1,
                :selector => { :deleteIndexes => "tribbles",
                               :index => "name_1" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/drop_index",
      "Datastore/statement/MongoDB/tribbles/drop_index"
    ]

    assert_equal expected, metrics
  end

  def test_metrics_for_reindex
    payload = { :database => "multiverse",
                :collection => "$cmd",
                :limit => -1,
                :selector => { :reIndex=> "tribbles" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = [
      "Datastore/all",
      "Datastore/operation/MongoDB/re_index",
      "Datastore/statement/MongoDB/tribbles/re_index"
    ]

    assert_equal expected, metrics
  end
end
