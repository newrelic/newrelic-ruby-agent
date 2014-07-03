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

  def test_attaches_cat_map_attributes_to_dirac_events
    get '/', { 'transaction_name' => 'foo', 'cross_app_caller' => '1' }

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    refute_empty(event[0]['nr.tripId'])
    assert_equal(event[0]['nr.tripId'], event[0]['nr.guid'])
    assert_equal(expected_path_hash,    event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_nil(event[0]['nr.referringTransactionGuid'])
  end

  def test_attaches_cat_map_attributes_to_dirac_events_with_referring_txn
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    get '/', { 'transaction_name' => 'foo' }, request_headers

    expected_path_hash = '1dcb7d6c'

    event = get_last_analytics_event

    assert_equal(calling_txn_guid,      event[0]['nr.tripId'])
    assert_equal(expected_path_hash,    event[0]['nr.pathHash'])
    assert_equal(calling_txn_path_hash, event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid,      event[0]['nr.referringTransactionGuid'])

    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  def test_handles_missing_referring_path_hash
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    # remove the referring path hash
    request_headers['X-NewRelic-Transaction'] = json_dump_and_encode([
      calling_txn_guid,
      false,
      calling_txn_guid
    ])

    get '/', { 'transaction_name' => 'foo' }, request_headers
    assert last_response.ok?

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    assert_equal(calling_txn_guid, event[0]['nr.tripId'])
    assert_equal(expected_path_hash, event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid, event[0]['nr.referringTransactionGuid'])
    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  def test_handles_null_referring_path_hash
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    request_headers['X-NewRelic-Transaction'] = json_dump_and_encode([
      calling_txn_guid,
      false,
      calling_txn_guid,
      nil
    ])

    get '/', { 'transaction_name' => 'foo' }, request_headers
    assert last_response.ok?

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    assert_equal(calling_txn_guid, event[0]['nr.tripId'])
    assert_equal(expected_path_hash, event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid, event[0]['nr.referringTransactionGuid'])
    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  def test_handles_malformed_referring_path_hash
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    request_headers['X-NewRelic-Transaction'] = json_dump_and_encode([
      calling_txn_guid,
      false,
      calling_txn_guid,
      ['scrambled', 'eggs']
    ])

    get '/', { 'transaction_name' => 'foo' }, request_headers
    assert last_response.ok?

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    assert_equal(calling_txn_guid, event[0]['nr.tripId'])
    assert_equal(expected_path_hash, event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid, event[0]['nr.referringTransactionGuid'])
    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  def test_handles_missing_trip_id
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    # old-style CAT headers without tripId or pathHash
    request_headers['X-NewRelic-Transaction'] = json_dump_and_encode([
      calling_txn_guid,
      false
    ])

    get '/', { 'transaction_name' => 'foo' }, request_headers
    assert last_response.ok?

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    refute_empty(event[0]['nr.guid'])
    refute_equal(event[0]['nr.guid'],   calling_txn_guid)
    assert_equal(event[0]['nr.tripId'], event[0]['nr.guid'])

    assert_equal(expected_path_hash, event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid, event[0]['nr.referringTransactionGuid'])
    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  def test_handles_null_trip_id
    calling_txn_guid, calling_txn_path_hash = generate_referring_transaction
    request_headers = generate_cat_headers(calling_txn_guid, calling_txn_path_hash)

    # old-style CAT headers without tripId or pathHash
    request_headers['X-NewRelic-Transaction'] = json_dump_and_encode([
      calling_txn_guid,
      false,
      nil
    ])

    get '/', { 'transaction_name' => 'foo' }, request_headers
    assert last_response.ok?

    expected_path_hash = 'c51bd2e'

    event = get_last_analytics_event

    refute_empty(event[0]['nr.guid'])
    refute_equal(event[0]['nr.guid'],   calling_txn_guid)
    assert_equal(event[0]['nr.tripId'], event[0]['nr.guid'])

    assert_equal(expected_path_hash, event[0]['nr.pathHash'])
    assert_nil(event[0]['nr.referringPathHash'])
    assert_equal(calling_txn_guid, event[0]['nr.referringTransactionGuid'])
    refute_empty(event[0]['nr.guid'])
    refute_equal(calling_txn_guid, event[0]['nr.guid'])
  end

  # Helpers

  def generate_referring_transaction
    calling_txn_guid      = nil
    calling_txn_path_hash = nil
    in_transaction('calling transaction') do |txn|
      state = NewRelic::Agent::TransactionState.tl_get
      calling_txn_guid      = txn.guid
      calling_txn_path_hash = txn.cat_path_hash(state)
    end
    [calling_txn_guid, calling_txn_path_hash]
  end

  def generate_cat_headers(guid, path_hash)
    {
      'X-NewRelic-ID'          => Base64.encode64('1#234'),
      'X-NewRelic-Transaction' => json_dump_and_encode([
        guid,
        false,
        guid,
        path_hash
      ])
    }
  end

  def get_last_analytics_event
    NewRelic::Agent.agent.instance_variable_get(:@request_sampler).samples.last
  end
end
