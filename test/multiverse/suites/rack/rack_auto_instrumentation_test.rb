# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-669

require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), 'example_app')

class RackAutoInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  def self.app
    @app ||= Rack::Builder.app do
      use MiddlewareOne
      use MiddlewareTwo
      run ExampleApp.new
    end
  end

  # Each test executes in a unique instance of RackAutoInstrumentationTest
  # We only want to build ExampleApp once so we need to use a class method.
  def app
    self.class.app
  end

  def test_middleware_gets_used
    get '/'
    assert last_response.headers['MiddlewareOne']
    assert last_response.headers['MiddlewareTwo']
  end

  def test_status_code_is_preserved
    get '/'
    assert_equal 200, last_response.status
  end

  def test_header_is_preserved
    get '/'
    assert last_response.headers['ExampleApp']
  end

  def test_body_is_preserved
    get '/'
    assert_equal 'A barebones rack app.', last_response.body
  end
end
