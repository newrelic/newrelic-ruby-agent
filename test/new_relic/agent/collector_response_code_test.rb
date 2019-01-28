# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'net/http'

module NewRelic
  module Agent
    class CollectorResponseCodeTest < Minitest::Test
      def setup
        @agent = NewRelic::Agent::Agent.new
        @errors = ["e1", "e2"]
      end

      def test_harvest_and_send_errors_discards_on_400
        stub_service Net::HTTPBadRequest.new('1.1', 400, 'Bad request')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_restarts_on_401
        stub_service Net::HTTPUnauthorized.new('1.1', 401, 'Unauthorized')

        # The error-handling code in agent.rb calls `retry`; rather
        # than testing it directly, we'll just assert that our service
        # call raises the right exception.
        #
        assert_raises(NewRelic::Agent::ForceRestartException) do
          @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
          @agent.send :harvest_and_send_errors
        end
      end

      def test_harvest_and_send_errors_discards_on_403
        stub_service Net::HTTPForbidden.new('1.1', 403, 'Forbidden')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_404
        stub_service Net::HTTPNotFound.new('1.1', 404, 'Not found')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_405
        stub_service Net::HTTPMethodNotAllowed.new('1.1', 405, 'Method not allowed')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_407
        stub_service Net::HTTPMethodNotAllowed.new('1.1', 407, 'Proxy authentication required')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_merges_back_on_408
        stub_service Net::HTTPRequestTimeOut.new('1.1', 408, 'Request timeout')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        @agent.error_collector.error_trace_aggregator.expects(:merge!).with(@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_restarts_on_409
        stub_service Net::HTTPUnauthorized.new('1.1', 409, 'Conflict')

        assert_raises(::NewRelic::Agent::ForceRestartException) do
          @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
          @agent.send :harvest_and_send_errors
        end
      end

      def test_harvest_and_send_errors_disconnects_on_410
        stub_service Net::HTTPGone.new('1.1', 410, 'Gone')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        @agent.expects(:disconnect)

        @agent.send(:catch_errors) do
          @agent.send :harvest_and_send_errors
        end
      end

      def test_harvest_and_send_errors_discards_on_411
        stub_service Net::HTTPLengthRequired.new('1.1', 411, 'Length required')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_413
        stub_service Net::HTTPRequestEntityTooLarge.new('1.1', 413, 'Too large')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_414
        stub_service Net::HTTPRequestURITooLong.new('1.1', 414, 'URI too long')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_415
        stub_service Net::HTTPUnsupportedMediaType.new('1.1', 415, 'Unsupported media type')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_417
        stub_service Net::HTTPExpectationFailed.new('1.1', 417, 'Expectation failed')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_merges_back_on_429
        stub_service Net::HTTPTooManyRequests.new('1.1', 429, 'Too many requests')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        @agent.error_collector.error_trace_aggregator.expects(:merge!).with(@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_431
        stub_service Net::HTTPRequestHeaderFieldsTooLarge.new('1.1', 431, 'Header fields too large')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_merges_back_on_500
        stub_service Net::HTTPInternalServerError.new('1.1', 500, 'Internal server error')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        @agent.error_collector.error_trace_aggregator.expects(:merge!).with(@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_merges_back_on_503
        stub_service Net::HTTPServiceUnavailable.new('1.1', 503, 'Service unavailable')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        @agent.error_collector.error_trace_aggregator.expects(:merge!).with(@errors)

        @agent.send :harvest_and_send_errors
      end

      def test_harvest_and_send_errors_discards_on_unknown_error
        stub_service Net::HTTPNotAcceptable.new('1.1', 406, 'Unacceptable!!')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
        assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)
        @agent.send :harvest_and_send_errors
      end

      def stub_service response
        conn = stub("http_connection", request: response)
        @agent.service.stubs(:http_connection).returns(conn)
      end
    end
  end
end
