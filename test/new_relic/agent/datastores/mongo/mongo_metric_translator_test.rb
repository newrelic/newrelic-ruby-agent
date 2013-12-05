# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/mongo_metric_translator'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::Datastores::Mongo::MetricTranslatorTest < Test::Unit::TestCase
  include ::NewRelic::TestHelpers::MongoMetricBuilder

  def setup
    @database_name = 'multiverse'
    @collection_name = 'tribbles'
  end

  def test_metrics_for_insert
    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:insert, { :collection => @collection_name })
    expected = build_test_metrics(:insert)

    assert_equal expected, metrics
  end

  def test_build_metrics_includes_web
    expected = [
      'Datastore/statement/MongoDB/tribbles/test',
      'Datastore/operation/MongoDB/test',
      'Datastore/all',
      'Datastore/allWeb'
    ]
    metrics = build_test_metrics('test')

    assert_equal expected, metrics
  end

  def test_build_metrics_includes_other
    expected = [
      'Datastore/statement/MongoDB/tribbles/test',
      'Datastore/operation/MongoDB/test',
      'Datastore/all',
      'Datastore/allOther'
    ]
    metrics = build_test_metrics('test', false)

    assert_equal expected, metrics
  end

  def test_metrics_for_find
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:find)

    assert_equal expected, metrics
  end

  def test_metrics_for_find_one
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => {},
                :limit      => -1 }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:find_one)

    assert_equal expected, metrics
  end

  def test_metrics_for_remove
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:remove, payload)
    expected = build_test_metrics(:remove)

    assert_equal expected, metrics
  end

  def test_metrics_for_update
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" },
                :document   => { "name" => "codemonkey" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:update, payload)
    expected = build_test_metrics(:update)

    assert_equal expected, metrics
  end

  def test_metrics_for_distinct
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :distinct => @collection_name,
                                 :key      => "name",
                                 :query    => nil } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:distinct, payload)
    expected = build_test_metrics(:distinct)

    assert_equal expected, metrics
  end

  def test_metrics_for_count
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "count"  => @collection_name,
                                 "query"  => {},
                                 "fields" => nil } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:count)

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_modify
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterios johnson" },
                                 :update        => {"name" => "codemonkey" } } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:find_and_modify)

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_remove
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterios johnson" },
                                 :remove        => true } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:find_and_remove)

    assert_equal expected, metrics
  end

  def test_metrics_for_create_index
    payload = { :database   => @database_name,
                :collection => "system.indexes",
                :documents  => [ { :name => "name_1",
                                    :ns   => "#{@database_name}.#{@collection_name}",
                                    :key  => { "name" => 1 } } ] }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:insert, payload)
    expected = build_test_metrics(:create_index)

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_indexes
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index         => "*" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:drop_indexes)

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_index
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index => "name_1" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:drop_index)

    assert_equal expected, metrics
  end

  def test_metrics_for_reindex
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :reIndex=> @collection_name } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:re_index)

    assert_equal expected, metrics
  end
end
