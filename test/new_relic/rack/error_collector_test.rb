require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/error_collector'

module NewRelic::Rack
  class ErrorCollectorTest < Test::Unit::TestCase
    include Rack::Test::Methods

    class TestApp
      def call(env)
        raise 'unhandled error'
      end
    end

    def app
      NewRelic::Rack::ErrorCollector.new(TestApp.new)
    end

    def setup
      NewRelic::Agent.reset_config
      NewRelic::Agent.manual_start
      NewRelic::Agent.instance.error_collector.errors = []

      # FIXME kick the error collector to make sure it's enabled
      NewRelic::Agent.instance.configure_error_collector!(true)
      assert NewRelic::Agent.instance.error_collector.enabled
    end

    def test_capture_raised_errors
      assert_raise RuntimeError do
        get '/'
      end

      assert_equal('unhandled error',
                   NewRelic::Agent.instance.error_collector.errors[0].message)
    end
  end
end
