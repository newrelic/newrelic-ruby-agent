# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'stripe'
require 'net/http'

class StripeInstrumentation < Minitest::Test
  API_KEY = '123456789'
  STRIPE_URL = 'Stripe/v1/customers/get'

  def setup
    Stripe.api_key = API_KEY
    # Creating a new connection and response, which both get stubbed
    # later, helps us get around needing to provide a valid API key
    @connection = Stripe::ConnectionManager.new
    @response = Net::HTTPResponse.new('1.1', '200', 'OK')
    # Bypass #stream_check ("attempt to read body out of block")
    @response.instance_variable_set(:@read, true)
    @response.body = {
      object: 'list',
      data: [{'id': '12134'}],
      has_more: false,
      url: STRIPE_URL
    }.to_json
  end

  def test_version_supported
    assert(Gem::Version.new(Stripe::VERSION) >= '5.38.0')
  end

  def test_subscribed_request_begin
    subcribers = Stripe::Instrumentation.send(:subscribers)
    newrelic_begin_subscriber = subcribers[:request_begin].detect { |_k, v| v.to_s.include?('instrumentation/stripe') }

    assert(newrelic_begin_subscriber)
  end

  def test_subscribed_request_end
    subcribers = Stripe::Instrumentation.send(:subscribers)
    newrelic_begin_subscriber = subcribers[:request_end].detect { |_k, v| v.to_s.include?('instrumentation/stripe') }

    assert(newrelic_begin_subscriber)
  end

  def test_newrelic_segment
    with_stubbed_connection_manager do
      in_transaction do |txn|
        start_stripe_event
        stripe_segment = stripe_segment_from_transaction(txn)

        assert(stripe_segment)
      end
    end
  end

  def test_agent_collects_user_data_attributes_when_configured
    Stripe::Instrumentation.subscribe(:request_begin) do |events|
      events.user_data[:cat] = 'meow'
      events.user_data[:dog] = 'woof'
    end

    with_config(:'stripe.user_data.include' => '.') do
      with_stubbed_connection_manager do
        in_transaction do |txn|
          start_stripe_event
          stripe_segment = stripe_segment_from_transaction(txn)

          assert(stripe_segment)
          stripe_attributes = stripe_segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)

          assert_equal('meow', stripe_attributes['stripe_user_data_cat'])
          assert_equal('woof', stripe_attributes['stripe_user_data_dog'])
        end
      end
    end
  end

  def test_agent_collects_select_user_data_attributes
    Stripe::Instrumentation.subscribe(:request_begin) do |events|
      events.user_data[:frog] = 'ribbit'
      events.user_data[:sheep] = 'baa'
      events.user_data[:cow] = 'moo'
    end

    with_config(:'stripe.user_data.include' => 'frog, sheep') do
      with_stubbed_connection_manager do
        in_transaction do |txn|
          start_stripe_event
          stripe_segment = stripe_segment_from_transaction(txn)

          assert(stripe_segment)
          stripe_attributes = stripe_segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)

          assert_equal('ribbit', stripe_attributes['stripe_user_data_frog'])
          assert_equal('baa', stripe_attributes['stripe_user_data_sheep'])
          assert_nil(stripe_attributes['stripe_user_data_cow'])
        end
      end
    end
  end

  def test_agent_ignores_user_data_attributes
    Stripe::Instrumentation.subscribe(:request_begin) do |events|
      events.user_data[:bird] = 'tweet'
    end

    with_config(:'stripe.user_data.exclude' => 'bird') do
      with_stubbed_connection_manager do
        in_transaction do |txn|
          start_stripe_event
          stripe_segment = stripe_segment_from_transaction(txn)

          assert(stripe_segment)
          stripe_attributes = stripe_segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)

          assert_nil(stripe_attributes['stripe_user_data_bird'])
        end
      end
    end
  end

  def test_start_when_not_traced
    with_stubbed_connection_manager do
      NewRelic::Agent::Tracer.state.stub(:is_execution_traced?, false) do
        in_transaction do |txn|
          start_stripe_event
          stripe_segment = stripe_segment_from_transaction(txn)

          refute stripe_segment
        end
      end
    end
  end

  def test_start_segment_records_error
    NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
      bad_event = OpenStruct.new(path: 'v1/charges', method: 'get')
      NewRelic::Agent::Instrumentation::StripeSubscriber.new.start_segment(bad_event)

      assert_logged(/Error starting New Relic Stripe segment/m)
    end
  end

  def start_stripe_event
    Stripe::Customer.list({limit: 3})
  end

  def stripe_segment_from_transaction(txn)
    txn.segments.detect { |s| s.name == STRIPE_URL }
  end

  def with_stubbed_connection_manager(&block)
    Stripe::StripeClient.stub(:default_connection_manager, @connection) do
      @connection.stub(:execute_request, @response) do
        yield
      end
    end
  end

  def assert_logged(expected)
    found = NewRelic::Agent.logger.messages.any? { |m| m[1][0].match?(expected) }

    assert(found, "Didn't see log message: '#{expected}'")
  end
end
