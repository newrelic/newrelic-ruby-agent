# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/cross_app_tracing'

module NewRelic
  module Agent
    class CrossAppTracingTest < Minitest::Test

      attr_reader :node, :request, :response

      def setup
        @node = stub_everything
        @request = stub_everything(:uri => URI.parse("http://newrelic.com"),
                                   :type => "Fake",
                                   :method => "GET")
        @response = stub_everything
        @state = NewRelic::Agent::TransactionState.tl_get
      end

      def test_start_trace
        t0   = Time.now
        node = CrossAppTracing.start_trace(@state, t0, request)
        refute_nil node
      end

      def test_start_trace_has_nil_node_on_agent_failure
        @state.traced_method_stack.stubs(:push_frame).raises("Boom!")
        t0      = Time.now
        node = CrossAppTracing.start_trace(@state, t0, request)
        assert_nil node
      end

      def test_finish_trace_treats_nil_start_time_as_agent_error
        expects_logging(:error, any_parameters)
        expects_no_pop_frame
        CrossAppTracing.finish_trace(@state, nil, node, request, response)
      end

      # Since we log and swallow errors, assert on the logging to ensure these
      # paths are cleanly accepting nils, not just smothering the exceptions.

      def test_finish_trace_allows_nil_node
        expects_no_logging(:error)
        CrossAppTracing.finish_trace(@state, Time.now, nil, request, response)
      end

      def test_finish_trace_allows_nil_request
        expects_no_logging(:error)
        expects_pop_frame
        CrossAppTracing.finish_trace(@state, Time.now, node, nil, response)
      end

      def test_finish_trace_allows_nil_response
        expects_no_logging(:error)
        expects_pop_frame
        CrossAppTracing.finish_trace(@state, Time.now, node, request, nil)
      end

      def expects_pop_frame
        @state.traced_method_stack.stubs(:pop_frame).once
      end

      def expects_no_pop_frame
        @state.traced_method_stack.stubs(:pop_frame).never
      end
    end
  end
end
