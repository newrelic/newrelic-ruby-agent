# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/instrumentation/middleware_tracing'

class NewRelic::Agent::Instrumentation::MiddlewareTracingTest < Minitest::Test
  class UserError < StandardError
  end

  class HostClass
    include NewRelic::Agent::Instrumentation::MiddlewareTracing

    attr_reader :category

    def initialize(&blk)
      @action = blk
    end

    def target
      self
    end

    def transaction_options
      {}
    end

    def traced_call(env)
      @action.call
    end
  end

  def test_dont_block_errors_during_malfunctioning_transaction
    NewRelic::Agent::Transaction.stubs(:start).returns(nil)

    middleware = HostClass.new { raise UserError }
    assert_raises(UserError) do
      middleware.call({})
    end
  end

  def test_dont_raise_when_transaction_start_fails
    NewRelic::Agent::Transaction.stubs(:start).returns(nil)

    middleware = HostClass.new { [200, {}, ['hi!']] }
    middleware.call({})
  end
end
