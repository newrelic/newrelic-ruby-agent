# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class NewRelic::Agent::Instrumentation::SequelInstrumentationTest < MiniTest::Unit::TestCase

  def test_mongo_instrumentation_loaded
    logging_methods = ::Mongo::Logging.instance_methods
    assert logging_methods.include?(:instrument_with_newrelic_trace), "Expected #{logging_methods.inspect}\n to include :instrument_with_newrelic_trace."
  end

  OPERATION_NAMES = {
    'find' => Proc.new { Tribble.find },
    'findOne' => Proc.new { Tribble.findOne },
    'insert' => Proc.new { Tribble.insert },
    'remove' => Proc.new { Tribble.remove },
    'save' => Proc.new { Tribble.save },
    'update' => Proc.new { Tribble.update },
    'distinct' => Proc.new { Tribble.distinct },
    'count' => Proc.new { Tribble.count },
    'findAndModify' => Proc.new { Tribble.findAndModify },
    'findAndRemove' => Proc.new { Tribble.findAndRemove },
    'createIndex' => Proc.new { Tribble.createIndex },
    'ensureIndex' => Proc.new { Tribble.ensureIndex },
    'dropIndex' => Proc.new { Tribble.dropIndex },
    'dropAllIndexes' => Proc.new { Tribble.dropAllIndexes },
    'reIndex' => Proc.new { Tribble.reIndex }
  }

  def test_instrumentation_records_metrics
    OPERATION_NAMES.each do |name, operation|
      in_web_transaction { operation.call }

      assert_metrics_recorded([
        "Datastore/all",
        "Datastore/operation/MongoDB/#{name}",
        "Datastore/statement/MongoDB/tribbles/#{name}"
      ])
    end
  end

end
