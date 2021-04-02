# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__
require 'new_relic/agent/instrumentation/sinatra'

class NewRelic::Agent::Instrumentation::SinatraTest < Minitest::Test

  # This fake app is not an actual Sinatra app to avoid having our unit tests
  # take a dependency directly on it. If you need actual Sinatra classes, go
  # write the test in the multiver suite.
  class SinatraTestApp
    include NewRelic::Agent::Instrumentation::Sinatra::Tracer

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

    state = NewRelic::Agent::Tracer.state

    assert_equal(@app.newrelic_request_headers(state), expected_headers)
  end

  def test_process_route_with_bad_arguments
    @app.stubs(:env).raises("Boo")
    yielded = false
    @app.process_route_with_tracing do 
      yielded = true
    end
    assert yielded 
  end

  def test_route_eval_with_bad_params
    @app.stubs(:env).raises("Boo")
    yielded = false
    @app.route_eval_with_tracing do 
      yielded = true
    end
    assert yielded 
  end

  def test_route_eval_without_last_route_doesnt_set_transaction_name
    @app.stubs(:env).returns({})
    @app.expects(:route_eval_with_tracing).once
    NewRelic::Agent.expects(:set_transaction_name).never
    @app.route_eval_with_tracing
  end

  def assert_transaction_name(expected, original)
    assert_equal expected, NewRelic::Agent::Instrumentation::Sinatra::TransactionNamer.transaction_name(original, nil)
  end
end
