# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/mongo_metric_translator'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::MongoMetricTranslatorTest < Test::Unit::TestCase
  def setup
    @database_name = 'multiverse'
    @collection_name = 'tribbles'
  end

  def test_metrics_for_insert
    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:insert, { :collection => @collection_name })
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:insert], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_find
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterious johnson" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:find], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_find_one
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => {},
                :limit      => -1 }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:find_one], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_remove
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterious johnson" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:remove, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:remove], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_update
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterious johnson" },
                :document   => { "name" => "codemonkey" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:update, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:update], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_distinct
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :distinct => @collection_name,
                                 :key      => "name",
                                 :query    => nil } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:distinct, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:distinct], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_count
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "count"  => @collection_name,
                                 "query"  => {},
                                 "fields" => nil } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:count], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_modify
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterious johnson" },
                                 :update        => {"name" => "codemonkey" } } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:find_and_modify], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_find_and_remove
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterious johnson" },
                                 :remove        => true } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:find_and_remove], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_create_index
    payload = { :database   => @database_name,
                :collection => "system.indexes",
                :documents  => [ { :name => "name_1",
                                    :ns   => "#{@database_name}.#{@collection_name}",
                                    :key  => { "name" => 1 } } ] }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:insert, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:create_index], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_indexes
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index         => "*" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:drop_indexes], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_index
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index => "name_1" } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:drop_index], @collection_name
    )

    assert_equal expected, metrics
  end

  def test_metrics_for_reindex
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :reIndex=> @collection_name } }

    metrics = NewRelic::Agent::MongoMetricTranslator.metrics_for(:find, payload)
    expected = NewRelic::Agent::MongoMetricTranslator.build_metrics(
      NewRelic::Agent::MONGO_METRICS[:re_index], @collection_name
    )

    assert_equal expected, metrics
  end
end
