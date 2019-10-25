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
end

class MinimalRackBody
  def initialize(body)
    @body = body
    @closed = false
  end

  def each
    @body.each { |part| yield part }
  end

  def close
    @closed = true
  end
end

class NewRelic::Agent::Instrumentation::RackTest < Minitest::Test

  def generate_minimal_rack_app mock_response
    generator = NewRelic::Agent::Instrumentation::MiddlewareProxy.for_class(MinimalRackApp)
    generator.new(mock_response)
  end

  def test_basic_rack_app
    # should return what we send in, even when instrumented
    x = generate_minimal_rack_app([200, {}, ["whee"]])
    assert_equal [200, {}, ["whee"]], x.call({})
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp/call'])
  end

  def test_streaming_rack_app
    # should return what we send in, even when instrumented
    body = MinimalRackBody.new(["whe", "e"])
    x = generate_minimal_rack_app([200, {}, body])
    status, headers, response = x.call({})

    full_body = ""
    response.each do |part|
      full_body += part
    end
    response.close

    assert_equal(200, status)
    assert_equal({}, headers)
    assert_equal("whee", full_body)
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp/call'])
    assert_metrics_recorded(['Middleware/Rack/StreamBodyProxy/body_each'])
    assert_metrics_recorded(['Middleware/Rack/StreamBodyProxy/close'])
  end

  def test_basic_rack_app_404
    x = generate_minimal_rack_app([404, {}, ["whee"]])
    assert_equal [404, {}, ["whee"]], x.call({})
    assert_metrics_recorded(['Controller/Middleware/Rack/MinimalRackApp/call'])
  end

  def test_does_not_double_instrument_middlewares
    x = generate_minimal_rack_app([200, {}, ["whee"]])
    wrapped_x = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(x)

    assert_same(x, wrapped_x)
  end
end
