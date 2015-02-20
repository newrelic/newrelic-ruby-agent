# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/mongo/metric_translator'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

class NewRelic::Agent::Datastores::Mongo::MetricTranslatorTest < Minitest::Test
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
    in_web_transaction do
      metrics = build_test_metrics('test')
      assert_includes metrics, 'Datastore/allWeb'
    end
  end

  def test_build_metrics_includes_other
    in_background_transaction do
      metrics = build_test_metrics('test')
      assert_includes metrics, 'Datastore/allOther'
    end
  end

  def test_build_metrics_includes_all_for_web
    in_web_transaction do
      metrics = build_test_metrics('test')
      assert_includes metrics, 'Datastore/all'
    end
  end

  def test_build_metrics_includes_all_for_other
    in_background_transaction do
      metrics = build_test_metrics('test')
      assert_includes metrics, 'Datastore/all'
    end
  end

  def test_build_metrics_is_graceful_if_exceptions_are_raised
    NewRelic::Agent::Datastores::MetricHelper.stubs(:metrics_for).raises("Boom")
    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, {})
    assert_empty metrics
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
    expected = build_test_metrics(:findOne)

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

  def test_metrics_for_group
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "group" => { "ns"      => @collection_name,
                                              "$reduce" => stub("BSON::Code"),
                                              "cond"    => {},
                                              "initial" => {:count=>0},
                                              "key"     => {"name"=>1}}}}

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:group)

    assert_equal expected, metrics
  end

  def test_metrics_for_aggregate
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   =>  { "aggregate" => @collection_name,
                                  "pipeline" => [{"$group" => {:_id => "$says", :total => {"$sum" => 1}}}]}}

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:aggregate)

    assert_equal expected, metrics
  end

  def test_metrics_for_mapreduce
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   =>  { "mapreduce" => @collection_name,
                                  "map" => stub("BSON::Code"),
                                  "reduce" => stub("BSON::Code"),
                                  :out => "results"}}

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:mapreduce)

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
    expected = build_test_metrics(:findAndModify)

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
    expected = build_test_metrics(:findAndRemove)

    assert_equal expected, metrics
  end

  def test_metrics_for_create_index
    payload = { :database   => @database_name,
                :collection => "system.indexes",
                :documents  => [ { :name => "name_1",
                                    :ns   => "#{@database_name}.#{@collection_name}",
                                    :key  => { "name" => 1 } } ] }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:insert, payload)
    expected = build_test_metrics(:createIndex)

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_indexes
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index         => "*" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:dropIndexes)

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_index
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index => "name_1" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:dropIndex)

    assert_equal expected, metrics
  end

  def test_metrics_for_reindex
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :reIndex=> @collection_name } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:reIndex)

    assert_equal expected, metrics
  end

  def test_metrics_for_drop_collection
    payload = { :database   => @database_name,
                :collection =>"$cmd",
                :limit      => -1,
                :selector   => { :drop => @collection_name } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:drop)

    assert_equal expected, metrics
  end

  def test_metrics_for_rename_collection
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :renameCollection => "#{@database_name}.#{@collection_name}",
                                 :to=>"#{@database_name}.renamed_#{@collection_name}" } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:renameCollection)

    assert_equal expected, metrics
  end

  def test_metrics_for_ismaster
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :ismaster => 1 } }

    @collection_name = "$cmd"

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:ismaster)

    assert_equal expected, metrics
  end

  def test_metrics_for_collstats
    payload = { :database   => @database_name,
                :collection =>"$cmd",
                :limit      => -1,
                :selector   => { :collstats => @collection_name } }

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:collstats)

    assert_equal expected, metrics
  end

  def test_metrics_for_unknown_command
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :mongomongomongo => @collection_name } }

    @collection_name = "$cmd"

    metrics = NewRelic::Agent::Datastores::Mongo::MetricTranslator.metrics_for(:find, payload)
    expected = build_test_metrics(:mongomongomongo)

    assert_equal expected, metrics
    assert_metrics_recorded(["Supportability/Mongo/UnknownCollection"])
  end
end
