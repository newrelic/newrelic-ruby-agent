# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/sinatra'

class NewRelic::Agent::Instrumentation::SinatraTest < Test::Unit::TestCase

  # This fake app is not an actual Sinatra app to avoid having our unit tests
  # take a dependency directly on it. If you need actual Sinatra classes, go
  # write the test in the multiver suite.
  class SinatraTestApp
    include NewRelic::Agent::Instrumentation::Sinatra

    attr_accessor :env, :request

    def initialize
      @env = {}
    end
  end


  def setup
    @app = SinatraTestApp.new
  end


  def test_newrelic_request_headers
    expected_headers = {:fake => :header}
    @app.request = mock('request', :env => expected_headers)

    assert_equal @app.newrelic_request_headers, expected_headers
  end

  def test_transaction_naming
    assert_transaction_name "(unknown)", "(unknown)"

    # Sinatra < 1.4 style regexes
    assert_transaction_name "will_boom", "^/will_boom$"
    assert_transaction_name "hello/([^/?#]+)", "^/hello/([^/?#]+)$"

    # Sinatra 1.4 style regexs
    assert_transaction_name "will_boom", "\A/will_boom\z"
    assert_transaction_name "hello/([^/?#]+)", "\A/hello/([^/?#]+)\z"
  end

  def test_process_route_with_bad_arguments
    @app.stubs(:env).throws("Boo")
    @app.expects(:process_route_without_newrelic).once
    @app.process_route_with_newrelic
  end

  def assert_transaction_name(expected, original)
    assert_equal expected, NewRelic::Agent::Instrumentation::Sinatra::NewRelic.transaction_name(original, nil)
  end
end
