# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/cross_app_tracing'

module NewRelic
  module Agent
    class CrossAppTracingTest < Minitest::Test

      attr_reader :segment, :request, :response

      def setup
        @segment = stub_everything
        @request = stub_everything(:uri => URI.parse("http://newrelic.com"),
                                   :type => "Fake",
                                   :method => "GET")
        @response = stub_everything
      end

      def test_start_trace
        t0, segment = CrossAppTracing.start_trace(request)
        refute_nil t0
        refute_nil segment
      end

      def test_start_trace_has_time_even_on_agent_failure
        NewRelic::Agent.instance.stats_engine.stubs(:push_scope).raises("Boom!")
        t0, segment = CrossAppTracing.start_trace(request)
        refute_nil t0
        assert_nil segment
      end

      # Since we log and swallow errors, assert on the logging to ensure these
      # paths are cleanly accepting nils, not just smothering the exceptions.

      def test_finish_trace_allows_nil_segment
        expects_no_logging(:error)
        CrossAppTracing.finish_trace(Time.now, nil, request, response)
      end

      def test_finish_trace_allows_nil_request
        expects_no_logging(:error)
        expects_pop_scope
        CrossAppTracing.finish_trace(Time.now, segment, nil, response)
      end

      def test_finish_trace_allows_nil_response
        expects_no_logging(:error)
        expects_pop_scope
        CrossAppTracing.finish_trace(Time.now, segment, request, nil)
      end


      def expects_pop_scope
        NewRelic::Agent.instance.stats_engine.stubs(:pop_scope).once
      end
    end
  end
end
