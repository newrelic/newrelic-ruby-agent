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

  def test_operation_and_collection_for_insert
    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:insert, { :collection => @collection_name })
    assert_equal ['insert', @collection_name], result
  end

  def test_operation_and_collection_for_is_graceful_if_exceptions_are_raised
    NewRelic::Agent::Datastores::Mongo::MetricTranslator.stubs(:find_one?).raises("Boom")
    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, {})
    assert_nil result
  end

  def test_operation_and_collection_for_find
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['find', @collection_name], result
  end

  def test_operation_and_collection_for_find_one
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => {},
                :limit      => -1 }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['findOne' ,@collection_name], result
  end

  def test_operation_and_collection_for_remove
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:remove, payload)

    assert_equal ['remove', @collection_name], result
  end

  def test_operation_and_collection_for_update
    payload = { :database   => @database_name,
                :collection => @collection_name,
                :selector   => { "name" => "soterios johnson" },
                :document   => { "name" => "codemonkey" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:update, payload)

    assert_equal ['update', @collection_name], result
  end

  def test_operation_and_collection_for_distinct
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :distinct => @collection_name,
                                 :key      => "name",
                                 :query    => nil } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:distinct, payload)

    assert_equal ['distinct', @collection_name], result
  end

  def test_operation_and_collection_for_count
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "count"  => @collection_name,
                                 "query"  => {},
                                 "fields" => nil } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['count', @collection_name], result
  end

  def test_operation_and_collection_for_group
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { "group" => { "ns"      => @collection_name,
                                              "$reduce" => stub("BSON::Code"),
                                              "cond"    => {},
                                              "initial" => {:count=>0},
                                              "key"     => {"name"=>1}}}}

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['group', @collection_name], result
  end

  def test_operation_and_collection_for_aggregate
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   =>  { "aggregate" => @collection_name,
                                  "pipeline" => [{"$group" => {:_id => "$says", :total => {"$sum" => 1}}}]}}

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['aggregate', @collection_name], result
  end

  def test_operation_and_collection_for_mapreduce
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   =>  { "mapreduce" => @collection_name,
                                  "map" => stub("BSON::Code"),
                                  "reduce" => stub("BSON::Code"),
                                  :out => "results"}}

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['mapreduce', @collection_name], result
  end


  def test_operation_and_collection_for_find_and_modify
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterios johnson" },
                                 :update        => {"name" => "codemonkey" } } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['findAndModify', @collection_name], result
  end

  def test_operation_and_collection_for_find_and_remove
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :findandmodify => @collection_name,
                                 :query         => { "name" => "soterios johnson" },
                                 :remove        => true } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['findAndRemove', @collection_name], result
  end

  def test_operation_and_collection_for_create_index
    payload = { :database   => @database_name,
                :collection => "system.indexes",
                :documents  => [ { :name => "name_1",
                                    :ns   => "#{@database_name}.#{@collection_name}",
                                    :key  => { "name" => 1 } } ] }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:insert, payload)

    assert_equal ['createIndex', @collection_name], result
  end

  def test_operation_and_collection_for_drop_indexes
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index         => "*" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['dropIndexes', @collection_name], result
  end

  def test_operation_and_collection_for_drop_index
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :deleteIndexes => @collection_name,
                               :index => "name_1" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['dropIndex', @collection_name], result
  end

  def test_operation_and_collection_for_reindex
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :reIndex=> @collection_name } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['reIndex', @collection_name], result
  end

  def test_operation_and_collection_for_drop_collection
    payload = { :database   => @database_name,
                :collection =>"$cmd",
                :limit      => -1,
                :selector   => { :drop => @collection_name } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['drop', @collection_name], result
  end

  def test_operation_and_collection_for_rename_collection
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :renameCollection => "#{@database_name}.#{@collection_name}",
                                 :to=>"#{@database_name}.renamed_#{@collection_name}" } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['renameCollection', @collection_name], result
  end

  def test_operation_and_collection_for_ismaster
    payload = { :database   => @database_name,
                :collection => "$cmd",
                :limit      => -1,
                :selector   => { :ismaster => 1 } }

    @collection_name = "$cmd"

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['ismaster', @collection_name], result
  end

  def test_operation_and_collection_for_collstats
    payload = { :database   => @database_name,
                :collection =>"$cmd",
                :limit      => -1,
                :selector   => { :collstats => @collection_name } }

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['collstats', @collection_name], result
  end

  def test_operation_and_collection_for_unknown_command
    payload = { :database => @database_name,
                :collection => "$cmd",
                :limit => -1,
                :selector => { :mongomongomongo => @collection_name } }

    @collection_name = "$cmd"

    result = NewRelic::Agent::Datastores::Mongo::MetricTranslator.operation_and_collection_for(:find, payload)

    assert_equal ['mongomongomongo', @collection_name], result
    assert_metrics_recorded(["Supportability/Mongo/UnknownCollection"])
  end
end
