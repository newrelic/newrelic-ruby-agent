# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < MiniTest::Unit::TestCase
  include Mongo

  def setup
    @client = MongoClient.new
    @database = @client.db('multiverse')
    @collection = @database.collection('tribbles')

    @tribble = {'name' => 'soterious johnson'}
  end

  def after_tests
    @client.drop_database('multiverse')
  end

  def test_generates_payload_metrics_for_an_operation
    ::NewRelic::Agent::MongoMetricTranslator.expects(:metrics_for).with(:insert, has_entry(:database => 'multiverse', :collection => 'tribbles'))
    @collection.insert(@tribble)
  end

  def test_mongo_instrumentation_loaded
    logging_methods = ::Mongo::Logging.instance_methods
    assert logging_methods.include?(:instrument_with_newrelic_trace), "Expected #{logging_methods.inspect}\n to include :instrument_with_newrelic_trace."
  end

  def test_records_metrics_for_insert
    @collection.insert(@tribble)

    metric = 'insert'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_find
    @collection.insert(@tribble)
    @collection.find(@tribble).to_a

    metric = 'find'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_find_one
    @collection.insert(@tribble)
    @collection.find_one

    metric = 'find_one'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_remove
    @collection.insert(@tribble)
    @collection.remove(@tribble).to_a

    metric = 'remove'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_save
    @collection.save(@tribble)

    metric = 'save'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_update
    updated = @tribble.dup
    updated['name'] = 'codemonkey'

    @collection.update(@tribble, updated)

    metric = 'update'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_distinct
    @collection.distinct('name')

    metric = 'distinct'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_count
    @collection.count

    metric = 'count'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_find_and_modify
    updated = @tribble.dup
    updated['name'] = 'codemonkey'
    @collection.find_and_modify(query: @tribble, update: updated)

    metric = 'find_and_modify'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_find_and_remove
    @collection.find_and_modify(query: @tribble, remove: true)

    metric = 'find_and_remove'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_create_index
    @collection.create_index({'name' => Mongo::ASCENDING})

    metric = 'create_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_ensure_index
    @collection.ensure_index({'name' => Mongo::ASCENDING})

    metric = 'ensure_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_drop_index
    @collection.create_index({'name' => Mongo::ASCENDING})
    name = @collection.index_information.values.last['name']
    @collection.drop_index(name)

    metric = 'drop_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_drop_indexes
    @collection.create_index({'name' => Mongo::ASCENDING})
    @collection.drop_indexes

    metric = 'drop_indexes'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

end
