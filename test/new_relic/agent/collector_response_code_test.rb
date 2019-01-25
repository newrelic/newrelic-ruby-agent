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
      end

      def test_harvest_and_send_errors_merges_back_on_429
        errors = [mock('e0'), mock('e1')]
        stub_service Net::HTTPTooManyRequests.new('1.1', 429, 'Too many requests')

        @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(errors)
        @agent.error_collector.error_trace_aggregator.expects(:merge!).with(errors)

        @agent.send :harvest_and_send_errors
      end

      def stub_service response
        conn = stub("http_connection", request: response)
        @agent.service.stubs(:http_connection).returns(conn)
      end
    end
  end
end
