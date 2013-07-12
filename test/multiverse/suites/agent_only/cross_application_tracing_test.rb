# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack/test'
require 'fake_collector'
require './testing_app'
require 'multiverse_helpers'

class CrossApplicationTracingTest < MiniTest::Unit::TestCase

  # Important because the hooks are global that we only wire one AgentHooks up
  @@app = TestingApp.new
  @@wrapper_app = NewRelic::Rack::AgentHooks.new(@@app)

  include MultiverseHelpers
  setup_and_teardown_agent(:cross_process_id => "boo",
                           :encoding_key => "\0",
                           :trusted_account_ids => [1]) \
  do |collector|
    collector.stub('connect', {"agent_run_id" => 666 })
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
end
