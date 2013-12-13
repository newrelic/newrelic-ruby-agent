# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'mongo_metric_builder')

class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < MiniTest::Unit::TestCase
  include Mongo
  include ::NewRelic::TestHelpers::MongoMetricBuilder

  def setup
    @client = MongoClient.new
    @database_name = 'multiverse'
    @database = @client.db(@database_name)
    @collection_name = 'tribbles'
    @collection = @database.collection(@collection_name)

    @tribble = {'name' => 'soterios johnson'}

    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    NewRelic::Agent.drop_buffered_data
  end

  def teardown
    NewRelic::Agent.drop_buffered_data
  end

  def test_records_metrics_for_insert
    @collection.insert(@tribble)

    metrics = build_test_metrics(:insert)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    @collection.find(@tribble).to_a

    metrics = build_test_metrics(:find)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_one
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    @collection.find_one

    metrics = build_test_metrics(:findOne)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_remove
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    @collection.remove(@tribble).to_a

    metrics = build_test_metrics(:remove)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_save
    @collection.save(@tribble)

    metrics = build_test_metrics(:save)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_save_does_not_record_insert
    @collection.save(@tribble)

    metrics = build_test_metrics(:save)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_not_recorded(['Datastore/operation/MongoDB/insert'])
  end

  def test_records_metrics_for_update
    updated = @tribble.dup
    updated['name'] = 'codemonkey'

    @collection.update(@tribble, updated)

    metrics = build_test_metrics(:update)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_distinct
    @collection.distinct('name')

    metrics = build_test_metrics(:distinct)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_count
    @collection.count

    metrics = build_test_metrics(:count)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_modify
    updated = @tribble.dup
    updated['name'] = 'codemonkey'
    @collection.find_and_modify(:query => @tribble, :update => updated)

    metrics = build_test_metrics(:findAndModify)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_remove
    @collection.find_and_modify(:query => @tribble, :remove =>true)

    metrics = build_test_metrics(:findAndRemove)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_create_index
    @collection.create_index([["name", Mongo::ASCENDING]])

    metrics = build_test_metrics(:createIndex)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_ensure_index
    @collection.ensure_index({'name' => Mongo::ASCENDING})

    metrics = build_test_metrics(:ensureIndex)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_ensure_index_does_not_record_insert
    @collection.ensure_index({'name' => Mongo::ASCENDING})

    assert_metrics_not_recorded(['Datastore/operation/MongoDB/insert'])
  end

  def test_records_metrics_for_drop_index
    name =  @collection.create_index([['name', Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    @collection.drop_index(name)

    metrics = build_test_metrics(:dropIndex)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_drop_indexes
    @collection.create_index([['name', Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    @collection.drop_indexes

    metrics = build_test_metrics(:dropIndexes)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_reindex
    @collection.create_index([['name', Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    @database.command({ :reIndex => @collection_name })

    metrics = build_test_metrics(:reIndex)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_notices_nosql
    segment = nil

    in_transaction do
      @collection.insert(@tribble)
      segment = find_last_transaction_segment
    end

    expected = { :database   => 'multiverse',
                 :collection => 'tribbles',
                 :operation  => :insert}

    result = segment.params[:statement]

    assert_equal expected, result, "Expected result (#{result}) to be #{expected}"
  end

  def test_noticed_nosql_includes_operation
    segment = nil

    in_transaction do
      @collection.insert(@tribble)
      segment = find_last_transaction_segment
    end

    expected = :insert

    query = segment.params[:statement]
    result = query[:operation]

    assert_equal expected, result
  end

  def test_noticed_nosql_includes_save_operation
    segment = nil

    in_transaction do
      @collection.save(@tribble)
      segment = find_last_transaction_segment
    end

    expected = :save

    query = segment.params[:statement]
    result = query[:operation]

    assert_equal expected, result
  end

  def test_noticed_nosql_includes_ensure_index_operation
    segment = nil

    in_transaction do
      @collection.ensure_index({'name' => Mongo::ASCENDING})
      segment = find_last_transaction_segment
    end

    expected = :ensureIndex

    query = segment.params[:statement]
    result = query[:operation]

    assert_equal expected, result
  end

  def test_noticed_nosql_does_not_contain_documents
    segment = nil

    in_transaction do
      @collection.insert({'name' => 'soterios johnson'})
      segment = find_last_transaction_segment
    end

    statement = segment.params[:statement]

    refute statement.keys.include?(:documents), "Noticed NoSQL should not include documents: #{statement}"
  end

  def test_web_requests_record_all_web_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    @collection.insert(@tribble)

    metrics = build_test_metrics(:insert)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_web_requests_do_not_record_all_other_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    @collection.insert(@tribble)

    assert_metrics_not_recorded(['Datastore/allOther'])
  end

  def test_other_requests_record_all_other_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
    @collection.insert(@tribble)

    metrics = build_test_metrics(:insert, :other)
    expected = metrics_with_attributes(metrics, { :call_count => 1 })

    assert_metrics_recorded(expected)
  end

  def test_other_requests_do_not_record_all_web_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
    @collection.insert(@tribble)

    assert_metrics_not_recorded(['Datastore/allWeb'])
  end

end
