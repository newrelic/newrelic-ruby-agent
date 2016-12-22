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

      def expects_pop_frame
        @state.traced_method_stack.stubs(:pop_frame).once
      end

      def expects_no_pop_frame
        @state.traced_method_stack.stubs(:pop_frame).never
      end
    end
  end
end
