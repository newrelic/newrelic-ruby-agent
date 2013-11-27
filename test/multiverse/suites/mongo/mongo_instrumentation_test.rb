# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','helpers','mongo_metric_builder'))

class NewRelic::Agent::Instrumentation::MongoInstrumentationTest < MiniTest::Unit::TestCase
  include Mongo
  include ::NewRelic::TestHelpers::MongoMetricBuilder

  def setup
    @client = MongoClient.new
    @database_name = 'multiverse'
    @database = @client.db(@database_name)
    @collection_name = 'tribbles'
    @collection = @database.collection(@collection_name)

    @tribble = {'name' => 'soterious johnson'}
  end

  def after_tests
    @client.drop_database(@database_name)
  end

  def test_generates_payload_metrics_for_an_operation
    ::NewRelic::Agent::MongoMetricTranslator.expects(:metrics_for).with(:insert, has_entry(:database => @database_name, :collection => @collection_name))
    @collection.insert(@tribble)
  end

  def test_mongo_instrumentation_loaded
    logging_methods = ::Mongo::Logging.instance_methods
    assert logging_methods.include?(:instrument_with_newrelic_trace), "Expected #{logging_methods.inspect}\n to include :instrument_with_newrelic_trace."
  end

  def test_records_metrics_for_insert
    @collection.insert(@tribble)

    expected = build_test_metrics(:insert)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find
    @collection.insert(@tribble)
    @collection.find(@tribble).to_a

    expected = build_test_metrics(:find)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_one
    @collection.insert(@tribble)
    @collection.find_one

    expected = build_test_metrics(:find_one)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_remove
    @collection.insert(@tribble)
    @collection.remove(@tribble).to_a

    expected = build_test_metrics(:remove)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_save
    @collection.save(@tribble)

    expected = build_test_metrics(:save)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_update
    updated = @tribble.dup
    updated['name'] = 'codemonkey'

    @collection.update(@tribble, updated)

    expected = build_test_metrics(:update)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_distinct
    @collection.distinct('name')

    expected = build_test_metrics(:distinct)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_count
    @collection.count

    expected = build_test_metrics(:count)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_modify
    updated = @tribble.dup
    updated['name'] = 'codemonkey'
    @collection.find_and_modify(query: @tribble, update: updated)

    expected = build_test_metrics(:find_and_modify)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_remove
    @collection.find_and_modify(query: @tribble, remove: true)

    expected = build_test_metrics(:find_and_remove)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_create_index
    @collection.create_index({'name' => Mongo::ASCENDING})

    expected = build_test_metrics(:create_index)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_ensure_index
    @collection.ensure_index({'name' => Mongo::ASCENDING})

    expected = build_test_metrics(:ensure_index)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_drop_index
    @collection.create_index({'name' => Mongo::ASCENDING})
    name = @collection.index_information.values.last['name']
    @collection.drop_index(name)

    expected = build_test_metrics(:drop_index)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_drop_indexes
    @collection.create_index({'name' => Mongo::ASCENDING})
    @collection.drop_indexes

    expected = build_test_metrics(:drop_indexes)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_reindex
    @collection.create_index({'name' => Mongo::ASCENDING})
    @database.command({ :reIndex => @collection_name })

    expected = build_test_metrics(:re_index)

    assert_metrics_recorded(expected)
  end

end
