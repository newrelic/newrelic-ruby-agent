require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/sinatra'

class NewRelic::Agent::Instrumentation::SinatraTest < Test::Unit::TestCase
  class SinatraTestApp
    def initialize(response)
      @response = response
    end

    def dispatch!
      @response = response
    end

    include NewRelic::Agent::Instrumentation::Sinatra
    alias dispatch_without_newrelic dispatch!
    alias dispatch! dispatch_with_newrelic
  end

  def test_newrelic_request_headers
    app = SinatraTestApp.new([200, {}, ["OK"]])
    expected_headers = {:fake => :header}
    app.expects(:request).returns(mock('request', :env => expected_headers))
    assert_equal app.send(:newrelic_request_headers), expected_headers
  end
end
