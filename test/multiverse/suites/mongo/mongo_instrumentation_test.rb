# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < MiniTest::Unit::TestCase
  include Mongo

  def setup
    @tribble = {'name' => 'soterious johnson'}
    @mongodb = MongoClient.new.db('multiverse')
    @tribbles = @mongodb.collection('tribbles')
  end

  def teardown
    # @mongodb.remove
  end

  def test_mongo_instrumentation_loaded
    logging_methods = ::Mongo::Logging.instance_methods
    assert logging_methods.include?(:instrument_with_newrelic_trace), "Expected #{logging_methods.inspect}\n to include :instrument_with_newrelic_trace."
  end

  def test_records_metrics_for_insert
    @tribbles.insert(@tribble)

    metric = 'insert'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_find
    @tribbles.insert(@tribble)
    @tribbles.find(@tribble).to_a

    metric = 'find'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_find_one
    @tribbles.insert(@tribble)
    @tribbles.find_one

    metric = 'find_one'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_remove
    @tribbles.insert(@tribble)
    @tribbles.remove(@tribble).to_a

    metric = 'remove'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_save
    @tribbles.save(@tribble)

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

    @tribbles.update(@tribble, updated)

    metric = 'update'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_distinct
    @tribbles.distinct('name')

    metric = 'distinct'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_count
    @tribbles.count

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
    @tribbles.find_and_modify(query: @tribble, update: updated)

    metric = 'findandmodify'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_find_and_remove
    @tribbles.find_and_modify(query: @tribble, remove: true)

    metric = 'findandremove'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_create_index
    @tribbles.create_index({'name' => Mongo::ASCENDING})

    metric = 'create_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_ensure_index
    @tribbles.ensure_index({'name' => Mongo::ASCENDING})

    metric = 'ensure_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_drop_index
    @tribbles.create_index({'name' => Mongo::ASCENDING})
    name = @tribbles.index_information.values.last['name']
    @tribbles.drop_index(name)

    metric = 'drop_index'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def test_records_metrics_for_drop_indexes
    @tribbles.drop_indexes

    metric = 'deleteIndexes'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

  def _test_records_metrics_for_reindex
    @tribbles.reindex

    metric = 'reindex'
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/operation/MongoDB/#{metric}",
      "Datastore/statement/MongoDB/tribbles/#{metric}"
    ])
  end

end
