# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack/test'
require 'new_relic/rack/browser_monitoring'
require './testing_app'

class RumAutoTest < Minitest::Test

  attr_reader :app

  include Rack::Test::Methods
  include MultiverseHelpers

  JS_AGENT_LOADER = "JS_AGENT_LOADER"

  LOADER_REGEX = "\n<script.*>JS_AGENT_LOADER</script>"
  CONFIG_REGEX = "\n<script.*>.*NREUM.info=.*</script>"

  setup_and_teardown_agent(:application_id => 'appId',
                           :beacon => 'beacon',
                           :browser_key => 'browserKey',
                           :js_agent_loader => JS_AGENT_LOADER) do |collector|
    collector.stub('connect', {
      'transaction_name_rules' => [{"match_expression" => "ignored_transaction",
                                    "ignore"           => true}],
      'agent_run_id' => 1,
    })
  end

  def after_setup
    @inner_app = TestingApp.new
    @app = NewRelic::Rack::BrowserMonitoring.new(@inner_app)
  end

  def test_autoinstrumentation_is_active
    @inner_app.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    get '/'
    assert_response_includes("<script", JS_AGENT_LOADER, "NREUM")
  end

  def test_autoinstrumentation_with_basic_page_puts_header_at_beginning_of_head
    @inner_app.response = "<html><head><title>foo</title></head><body><p>Hello World</p></body></html>"
    get '/'
    assert_response_includes(%Q[<html><head>#{CONFIG_REGEX}#{LOADER_REGEX}<title>foo</title></head>])
  end

  def test_autoinstrumentation_with_body_only_puts_header_before_body
    @inner_app.response = "<html><body><p>Hello World</p></body></html>"
    get '/'
    assert_response_includes %Q[<html>#{CONFIG_REGEX}#{LOADER_REGEX}<body>]
  end

  def test_autoinstrumentation_with_X_UA_Compatible_puts_header_after_meta_tag
    @inner_app.response = '<html><head><meta http-equiv="X-UA-Compatible"/></head><body><p>Hello World</p></body></html>'
    get '/'
    assert_response_includes(%Q[<html><head><meta http-equiv="X-UA-Compatible"/>#{CONFIG_REGEX}#{LOADER_REGEX}</head><body>])
  end

  def test_autoinstrumentation_doesnt_run_for_crazy_shit_like_this
    @inner_app.response = '<html><head <body </body>'
    get '/'
    assert_response_includes('<html><head <body </body>')
  end

  def test_content_length_is_correctly_set_if_present
    @inner_app.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    content_length = @inner_app.response.length
    @inner_app.headers["Content-Length"] = content_length
    get '/'
    assert(last_response.headers['Content-Length'].to_i > content_length)
    assert_equal(last_response.body.length.to_s, last_response.headers['Content-Length'])
  end

  def test_xml_responses_arent_instrumented
    body = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    @inner_app.response = body
    @inner_app.headers["Content-Type"] = "text/xml"
    get '/'
    assert_equal(last_response.body, body)
  end

  def test_rum_headers_are_not_injected_in_ignored_txn
    body = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    @inner_app.response = body
    get '/', 'transaction_name' => 'ignored_transaction'
    assert_equal(last_response.body, body)
  end

  def assert_response_includes(*texts)
    texts.each do |text|
      assert_match(Regexp.new(text), last_response.body,
                   "Response missing #{text} for JS Agent instrumentation:\n #{last_response.body}")
    end
  end
end
