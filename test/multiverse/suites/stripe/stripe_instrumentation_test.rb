# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'ostruct'
require 'stripe'

class StripeInstrumentation < Minitest::Test
  API_KEY = '123456789'
  STRIPE_URL = 'Stripe/v1/customers/get'
  DummyEvent = Struct.new(:path, :method)

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
    assert(NewRelic::Helper.version_satisfied?(Stripe::VERSION, '>=', '5.38.0'))
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

    with_config('stripe.user_data.include': %w[.],
      'stripe.user_data.exclude': %w[bird]) do
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

  def test_agent_ignores_user_data_values
    Stripe::Instrumentation.subscribe(:request_begin) do |events|
      events.user_data[:contact_name] = 'Jenny'
      events.user_data[:contact_phone] = '867-5309'
    end

    with_config('stripe.user_data.include': %w[.],
      'stripe.user_data.exclude': ['^\d{3}-\d{4}$']) do
      with_stubbed_connection_manager do
        in_transaction do |txn|
          start_stripe_event
          stripe_segment = stripe_segment_from_transaction(txn)

          assert(stripe_segment)
          stripe_attributes = stripe_segment.attributes.agent_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)

          assert(stripe_attributes['stripe_user_data_contact_name'])
          assert_nil(stripe_attributes['stripe_user_data_contact_phone'])
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

  def test_metric_names_are_not_specific_enough_to_cause_a_cardinality_explosion
    categories = %w[Trzy_kolory The_Apu_Trilogy The_Lord_of_the_Rings]
    paths = ["/v1/#{categories[0]}/Niebieski",
      "/v1/#{categories[0]}/Biały",
      "/v1/#{categories[0]}/Czerwony",
      "/v1/#{categories[1]}/Pather_Panchali",
      "/v1/#{categories[1]}/Aparajito",
      "/v1/#{categories[1]}/The_World_of_Apu",
      "/v1/#{categories[2]}/The_Fellowship_of_the_Ring",
      "/v1/#{categories[2]}/The_Two_Towers",
      "/v1/#{categories[2]}/The_Return_of_the_King"]
    method = 'get'

    subscriber = NewRelic::Agent::Instrumentation::StripeSubscriber.new
    expected = categories.map { |c| Array.new(3) { "Stripe/v1/#{c}/#{method}" } }.flatten
    actual = paths.map { |p| subscriber.send(:metric_name, DummyEvent.new(p, method)) }

    assert_equal expected, actual,
      "Expected everything after the category in each path to be stripped away. Expected: #{expected} Actual: #{actual}"
  end

  def start_stripe_event
    Stripe::Customer.list({limit: 3})
  end

  def stripe_segment_from_transaction(txn)
    txn.segments.detect { |s| s.name == STRIPE_URL }
  end

  def with_stubbed_connection_manager(&block)
    # Stripe moved StripeClient and requestor logic to APIRequestor in v13.0.0
    # https://github.com/stripe/stripe-ruby/pull/1458
    if NewRelic::Helper.version_satisfied?(Stripe::VERSION, '>=', '13.0.0')
      Stripe::APIRequestor.stub(:default_connection_manager, @connection) do
        @connection.stub(:execute_request, @response) do
          yield
        end
      end
    else
      Stripe::StripeClient.stub(:default_connection_manager, @connection) do
        @connection.stub(:execute_request, @response) do
          yield
        end
      end
    end
  end

  def assert_logged(expected)
    found = NewRelic::Agent.logger.messages.any? { |m| m[1][0].match?(expected) }

    assert(found, "Didn't see log message: '#{expected}'")
  end
end
