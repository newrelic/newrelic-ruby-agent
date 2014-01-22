# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/rack/transaction_reset'
require 'new_relic/agent/transaction_state'

module NewRelic
  module Rack
    class TransactionResetTest < MiniTest::Unit::TestCase
      class ExampleMiddleware
        include TransactionReset
      end

      attr_reader :middleware, :env

      def setup
        @middleware = ExampleMiddleware.new
        @env = {}
      end

      def test_resets
        NewRelic::Agent::TransactionState.expects(:reset).once
        middleware.ensure_transaction_reset(env)
      end

      def test_resets_only_once
        NewRelic::Agent::TransactionState.expects(:reset).once
        middleware.ensure_transaction_reset(env)
        middleware.ensure_transaction_reset(env)
      end
    end
  end
end
