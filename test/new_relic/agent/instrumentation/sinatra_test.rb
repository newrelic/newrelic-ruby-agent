# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/sinatra'

class NewRelic::Agent::Instrumentation::SinatraTest < Minitest::Test

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

    state = NewRelic::Agent::TransactionState.tl_get

    assert_equal(@app.newrelic_request_headers(state), expected_headers)
  end

  def test_process_route_with_bad_arguments
    @app.stubs(:env).raises("Boo")
    @app.expects(:process_route_without_newrelic).once
    @app.process_route_with_newrelic
  end

  def test_route_eval_with_bad_params
    @app.stubs(:env).raises("Boo")
    @app.expects(:route_eval_without_newrelic).once
    @app.route_eval_with_newrelic
  end

  def test_route_eval_without_last_route_doesnt_set_transaction_name
    @app.stubs(:env).returns({})
    @app.expects(:route_eval_without_newrelic).once
    NewRelic::Agent.expects(:set_transaction_name).never
    @app.route_eval_with_newrelic
  end

  def test_injects_middleware
    SinatraTestApp.stubs(:middleware).returns([])

    SinatraTestApp.expects(:build_without_newrelic).once
    SinatraTestApp.expects(:use).at_least(2)

    SinatraTestApp.build_with_newrelic(@app)
  end

  def test_doesnt_inject_already_existing_middleware
    default_middlewares = SinatraTestApp.newrelic_middlewares
    # mock up the return value of Sinatra's #middleware method, which returns an
    # Array of Arrays.
    middleware_info = default_middlewares.map { |m| [m] }
    SinatraTestApp.stubs(:middleware).returns(middleware_info)

    SinatraTestApp.expects(:build_without_newrelic).once
    SinatraTestApp.expects(:use).never

    SinatraTestApp.build_with_newrelic(@app)
  end

  def assert_transaction_name(expected, original)
    assert_equal expected, NewRelic::Agent::Instrumentation::Sinatra::TransactionNamer.transaction_name(original, nil)
  end
end
