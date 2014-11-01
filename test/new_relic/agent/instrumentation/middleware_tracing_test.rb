# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/middleware_tracing'

class NewRelic::Agent::Instrumentation::MiddlewareTracingTest < Minitest::Test
  class UserError < StandardError
  end

  def test_dont_block_errors_during_malfunctioning_transaction
    middleware_class = Class.new do
      include NewRelic::Agent::Instrumentation::MiddlewareTracing

      attr_reader :category

      def target
        self
      end

      def transaction_options
        {}
      end

      def traced_call(env)
        raise UserError.new
      end
    end

    NewRelic::Agent::Transaction.stubs(:start).returns(nil)

    assert_raises(UserError) do
      middleware_class.new.call({})
    end
  end
end
