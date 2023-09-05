# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/stripe'
require 'new_relic/agent/instrumentation/stripe_subscriber'

class StripeSubscriberTest < Minitest::Test
  def setup
    @request_begin_event = mock('request_begin_event')
    @request_begin_event.stubs(:method).returns(:get)
    @request_begin_event.stubs(:path).returns('/v1/customers')
    @request_begin_event.stubs(:user_data).returns({})

    @request_end_event = mock('request_end_event')
    @request_end_event.stubs(:duration).returns(0.3654450001195073)
    @request_end_event.stubs(:http_status).returns(200)
    @request_end_event.stubs(:method).returns(:get)
    @request_end_event.stubs(:num_retries).returns(0)
    @request_end_event.stubs(:path).returns('/v1/customers')
    @request_end_event.stubs(:request_id).returns('req_xKEDn4mD5zCBGw')
    newrelic_segment = NewRelic::Agent::Tracer.start_segment(name: 'Stripe/v1/customers get')
    @request_end_event.stubs(:user_data).returns({:newrelic_segment => newrelic_segment, :cat => 'meow'})

    @subscriber = NewRelic::Agent::Instrumentation::StripeSubscriber.new
  end

  def test_start_segment_sets_newrelic_segment
    @subscriber.start_segment(@request_begin_event)

    assert(@request_begin_event.user_data[:newrelic_segment])
  end

  def test_metric_name_set
    name = @subscriber.metric_name(@request_begin_event)

    assert_equal('Stripe/v1/customers get', name)
  end

  def test_finish_segment_removes_newrelic_segment
    @subscriber.finish_segment(@request_end_event)

    assert_nil(@request_begin_event.user_data[:newrelic_segment])
  end
end
