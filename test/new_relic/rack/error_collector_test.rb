# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/error_collector'

module NewRelic::Rack
  class ErrorCollectorTest < Minitest::Test
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
      NewRelic::Agent.instance.error_collector.drop_buffered_data

      # sanity checks
      assert NewRelic::Agent.instance.error_collector.enabled?
    end

    def test_notice_and_reraise_errors
      assert_raises RuntimeError do
        get '/'
      end

      assert_equal('unhandled error', last_error.message)
    end

    def test_ignore_filtered_errors
      filter = Proc.new do |error|
        !error.kind_of?(RuntimeError)
      end

      with_ignore_error_filter(filter) do
        assert_raises RuntimeError do
          get '/'
        end
      end

      errors = harvest_error_traces!
      assert(errors.empty?,
             'noticed an error that should have been ignored')
    end

    # Ideally we'd test this for failures to create Rack::Request as well,
    # but unfortunately rack-test, which we're using to drive, creates
    # Rack::Request objects internally, so there's not an easy way to.
    def test_handles_failure_to_create_request_object
      if defined?(ActionDispatch::Request)
        ActionDispatch::Request.stubs(:new).raises('bad news')

        assert_raises RuntimeError do
          get '/foo/bar?q=12'
        end
        error = last_error

        assert_equal('unhandled error', error.message)
        assert_equal('/foo/bar', error.request_uri)
      end
    end

    def last_error
      harvest_error_traces!.last
    end
  end
end
