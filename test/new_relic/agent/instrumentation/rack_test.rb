# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/rack'

class MinimalRackApp
  def initialize(return_value)
    @return_value = return_value
  end

  def call(env)
    @return_value
  end

  include NewRelic::Agent::Instrumentation::Rack
end

class NewRelic::Agent::Instrumentation::RackTest < Minitest::Test
  def test_basic_rack_app
    # should return what we send in, even when instrumented
    x = MinimalRackApp.new([200, {}, ["whee"]])
    assert_equal [200, {}, ["whee"]], x.call({})
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp'])
  end

  def test_basic_rack_app_404
    x = MinimalRackApp.new([404, {}, ["whee"]])
    assert_equal [404, {}, ["whee"]], x.call({})
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp'])
  end

  def test_basic_rack_app_ignores_404
    NewRelic::Agent::Transaction.expects(:abort_transaction!)
    x = MinimalRackApp.new([404, {}, ["whee"]])
    assert_equal [404, {}, ["whee"]], x.call({})
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp'])
  end

  def test_does_not_double_instrument_middlewares
    x = MinimalRackApp.new([200, {}, ["whee"]])
    wrapped_x = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(x)

    assert_same(x, wrapped_x)
  end
end
