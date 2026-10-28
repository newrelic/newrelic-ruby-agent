# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
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
    NewRelic::Agent::Tracer.stubs(:start_transaction_or_segment).returns(nil)

    middleware = HostClass.new { raise UserError }
    assert_raises(UserError) do
      middleware.call({})
    end
  end

  def test_dont_raise_when_transaction_start_fails
    NewRelic::Agent::Tracer.stubs(:start_transaction_or_segment).returns(nil)

    middleware = HostClass.new { [200, {}, ['hi!']] }
    middleware.call({})
  end

  def test_captures_lowercase_response_headers
    txn = capture_response_headers('content-type' => 'text/html', 'content-length' => '42')

    assert_equal 'text/html', txn.response_content_type
    assert_equal '42', txn.response_content_length
  end

  def test_sums_lowercase_array_content_length
    txn = capture_response_headers('content-length' => %w[10 32])

    assert_equal 42, txn.response_content_length
  end

  private

  def capture_response_headers(headers)
    txn = nil
    in_transaction do |t|
      txn = t
      HostClass.new.capture_response_attributes(NewRelic::Agent::Tracer.state, [200, headers, []])
    end
    txn
  end
end
