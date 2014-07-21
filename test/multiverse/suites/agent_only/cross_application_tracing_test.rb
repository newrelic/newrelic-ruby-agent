# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack/test'
require 'fake_collector'
require './testing_app'
require 'multiverse_helpers'
require 'new_relic/rack/agent_hooks'

class CrossApplicationTracingTest < Minitest::Test

  # Important because the hooks are global that we only wire one AgentHooks up
  @@app = TestingApp.new
  @@wrapper_app = NewRelic::Rack::AgentHooks.new(@@app)

  include MultiverseHelpers
  setup_and_teardown_agent(:cross_process_id => "boo",
                           :encoding_key => "\0",
                           :trusted_account_ids => [1]) \
  do |collector|
    collector.stub('connect', {
      'agent_run_id' => 666,
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore"           => true}]})
  end

  def after_setup
    @@app.reset_headers
    @@app.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
  end

  include Rack::Test::Methods

  def app
    @@wrapper_app
  end

  def test_cross_app_doesnt_modify_without_header
    get '/'
    assert_nil last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_doesnt_modify_with_invalid_header
    get '/', nil, {'X-NewRelic-ID' => Base64.encode64('otherjunk')}
    assert_nil last_response.headers["X-NewRelic-App-Data"]
  end

  def test_cross_app_writes_out_information
    get '/', nil, {'X-NewRelic-ID' => Base64.encode64('1#234')}
    refute_nil last_response.headers["X-NewRelic-App-Data"]
    assert_metrics_recorded(['ClientApplication/1#234/all'])
  end

  def test_cross_app_doesnt_modify_if_txn_is_ignored
    get '/', {'transaction_name' => 'ignored_transaction'}, {'X-NewRelic-ID' => Base64.encode64('1#234')}
    assert_nil last_response.headers["X-NewRelic-App-Data"]
  end

  load_cross_agent_test("cat_map").each do |test_case|
    # We only can do test cases here that don't involve outgoing calls 
    if !test_case["outgoingTxnNames"]
      if test_case['referringPayload']
        request_headers = {
          'X-NewRelic-ID'          => Base64.encode64('1#234'),
          'X-NewRelic-Transaction' => json_dump_and_encode(test_case['referringPayload'])
        }
      else
        request_headers = {}
      end

      define_method("test_#{test_case['name']}") do
        txn_category, txn_name = test_case['transactionName'].split('/')
        request_params = {
          'transaction_name' => txn_name,
          'transaction_category' => txn_category,
          'guid' => test_case['transactionGuid']
        }

        with_config('app_name' => test_case['appName']) do
          get '/', request_params, request_headers
        end

        event = get_last_analytics_event
        assert_event_attributes(event, test_case['name'], test_case['expectedAttributes'], test_case['nonExpectedAttributes'])
      end
    end
  end
end
