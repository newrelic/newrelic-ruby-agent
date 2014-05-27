# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Rack::DeferredInstrumentationTest < Minitest::Test
  class TestApp
    def call(env)
      [200, {}, ["whatever"]]
    end
  end

  def test_to_app_does_not_blow_up_when_rack_instrumentation_required_multiple_times
    # We want to use two different paths to require the rack instrumentation here
    # in order to simulate a situation that might arise where a user is
    # explicitly requiring our rack instrumentation file, and then the agent
    # automatically requires it as well, via a different path.
    # On Ruby 1.8.7, this will cause the file to be evaluated multiple times.
    path1 = "new_relic/agent/instrumentation/rack"
    path2 = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'new_relic', 'agent', 'instrumentation', 'rack'))
    refute_equal(path2, path1)

    require path1
    require path2

    builder = ::Rack::Builder.new do
      run(::NewRelic::Rack::DeferredInstrumentationTest::TestApp.new)
    end

    builder.to_app
  end
end
