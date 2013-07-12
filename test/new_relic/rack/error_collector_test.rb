# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/error_collector'

module NewRelic::Rack
  class ErrorCollectorTest < Test::Unit::TestCase
    include Rack::Test::Methods

    class TestApp
      def call(env)
        if env['PATH_INFO'] == '/ignored'
          env['action_dispatch.request.parameters'] = {
            'controller' => 'test_ignore',
            'action'     => 'ignored'
          }
        end
        raise 'unhandled error'
      end
    end

    def app
      NewRelic::Rack::ErrorCollector.new(TestApp.new)
    end

    def setup
      NewRelic::Agent.reset_config
      NewRelic::Agent.manual_start
      NewRelic::Agent.instance.error_collector
      NewRelic::Agent.instance.error_collector.errors = []

      # sanity checks
      assert NewRelic::Agent.instance.error_collector.enabled?
      NewRelic::Agent.instance.error_collector \
        .instance_variable_set(:@ignore_filter, nil)
      assert !NewRelic::Agent.instance.error_collector.ignore_error_filter
    end

    def test_notice_and_reraise_errors
      assert_raise RuntimeError do
        get '/'
      end

      assert_equal('unhandled error', last_error.message)
    end

    def test_ignore_filtered_errors
      NewRelic::Agent.instance.error_collector.ignore_error_filter do |error|
        !error.kind_of?(RuntimeError)
      end

      assert_raise RuntimeError do
        get '/'
      end

      assert(NewRelic::Agent.instance.error_collector.errors.empty?,
             'noticed an error that should have been ignored')
    end

    if defined?(::Rails)
      def test_ignore_errors_from_ignored_actions
        assert_raise RuntimeError do
          get '/ignored'
        end

        assert(NewRelic::Agent.instance.error_collector.errors.empty?,
               'noticed an error that should have been ignored')
      end
    else
      puts "Skipping tests in #{__FILE__} because Rails is unavailable"
    end

    def test_handles_parameter_parsing_exceptions
      if defined?(ActionDispatch::Request)
        bad_request = stub.stubs(:filtered_params).raises(TypeError, "can't convert nil into Hash")
        ActionDispatch::Request.stubs(:new).returns(bad_request)
      else
        bad_request = stub(:env => {}, :path => '/', :referer => '')
        bad_request.stubs(:params).raises(TypeError, "whatever, man")
        Rack::Request.stubs(:new).returns(bad_request)
      end

      assert_raise RuntimeError do
        get '/'
      end

      assert_equal('unhandled error', last_error.message)
      assert_match(/failed to capture request parameters/i,
                   last_error.params[:request_params]['error'])
    end

    # Ideally we'd test this for failures to create Rack::Request as well,
    # but unfortunately rack-test, which we're using to drive, creates
    # Rack::Request objects internally, so there's not an easy way to.
    def test_handles_failure_to_create_request_object
      if defined?(ActionDispatch::Request)
        ActionDispatch::Request.stubs(:new).raises('bad news')

        assert_raise RuntimeError do
          get '/foo/bar?q=12'
        end

        assert_equal('unhandled error', last_error.message)
        assert_equal('/foo/bar', last_error.params[:request_uri])
      end
    end

    def test_captures_parameters_with_rails
      assert_raise RuntimeError do
        get '/?foo=bar&baz=qux'
      end

      expected_params = { 'foo' => 'bar', 'baz' => 'qux' }
      assert_equal('unhandled error', last_error.message)
      assert_equal(expected_params, last_error.params[:request_params])
    end

    def test_captures_parameters_without_rails
      undefine_constant(:'ActionDispatch::Request') do
        assert_raise RuntimeError do
          get '/?foo=bar&baz=qux'
        end
      end

      expected_params = { 'foo' => 'bar', 'baz' => 'qux' }
      assert_equal('unhandled error', last_error.message)
      assert_equal(expected_params, last_error.params[:request_params])
    end

    def last_error
      NewRelic::Agent.instance.error_collector.errors[0]
    end
  end
end

class TestIgnoreController
  @do_not_trace = { :only => :ignored }
end
