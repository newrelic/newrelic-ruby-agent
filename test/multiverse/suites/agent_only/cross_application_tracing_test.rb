# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'rack/test'
require 'fake_collector'
require './testing_app'
require 'new_relic/rack/agent_hooks'

class CrossApplicationTracingTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent(:'cross_application_tracer.enabled' => true,
    :'distributed_tracing.enabled' => false,
    :cross_process_id => "boo",
    :encoding_key => "\0",
    :trusted_account_ids => [1]) \
  do |collector|
    collector.stub('connect', {
      'agent_run_id' => 666,
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore" => true}]
    })
  end

  include Rack::Test::Methods

  def app
    Rack::Builder.app { run TestingApp.new }
  end

  def test_cross_app_doesnt_modify_without_header
    get '/'
    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_doesnt_modify_with_invalid_header
    get '/', nil, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('otherjunk')}
    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_writes_out_information
    get '/', nil, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')}
    refute_nil last_response.headers["X-NewRelic-App-Data"]
    assert_metrics_recorded(['ClientApplication/1#234/all'])
  end

  def test_cross_app_doesnt_modify_if_txn_is_ignored
    get '/', {'transaction_name' => 'ignored_transaction'}, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')}
    refute last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_error_attaches_process_id_to_intrinsics
    assert_raises(RuntimeError) do
      get '/', {'fail' => 'true'}, {'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234')}
    end

    assert_includes attributes_for(last_traced_error, :intrinsic), :client_cross_process_id
  end

  load_cross_agent_test("cat_map").each do |test_case|
    # We only can do test cases here that don't involve outgoing calls
    if !test_case["outboundRequests"]
      if test_case['inboundPayload']
        request_headers = {
          'HTTP_X_NEWRELIC_ID' => Base64.encode64('1#234'),
          'HTTP_X_NEWRELIC_TRANSACTION' => json_dump_and_encode(test_case['inboundPayload'])
        }
      else
        request_headers = {}
      end

      define_method("test_#{test_case['name']}") do
        txn_name_parts = test_case['transactionName'].split('/')
        txn_category = txn_name_parts[0..1].join('/')
        txn_name = txn_name_parts[2..-1].join('/')

        request_params = {
          'transaction_name' => txn_name,
          'transaction_category' => txn_category,
          'guid' => test_case['transactionGuid']
        }

        with_config('app_name' => test_case['appName'],
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled'      => false) do
          get '/', request_params, request_headers
        end

        event = get_last_analytics_event
        assert_event_attributes(
          event,
          test_case['name'],
          test_case['expectedIntrinsicFields'],
          test_case['nonExpectedIntrinsicFields']
        )
      end
    end
  end
end
