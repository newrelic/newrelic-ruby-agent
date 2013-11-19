# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'mongo'
require 'newrelic_rpm'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

class NewRelic::Agent::Instrumentation::SequelInstrumentationTest < MiniTest::Unit::TestCase

  def test_that_mongo_instrumentation_loaded
    logging_methods = ::Mongo::Logging.methods
    assert logging_methods.include?(:instrument_with_newrelic_trace), "Expected #{logging_methods.inspect}\n to include :instrument_with_newrelic_trace."
  end

end
