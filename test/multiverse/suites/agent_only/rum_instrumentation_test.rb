# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack/test'
require 'new_relic/rack/browser_monitoring'
require './testing_app'
require 'multiverse_helpers'

class RumAutoTest < MiniTest::Unit::TestCase

  attr_reader :app

  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent(:browser_key => 'browserKey', :application_id => 'appId',
                            :beacon => 'beacon', :episodes_file => 'this_is_my_file')

  def after_setup
    @inner_app = TestingApp.new
    @app = NewRelic::Rack::BrowserMonitoring.new(@inner_app)
  end

  def test_autoinstrumentation_is_active
    @inner_app.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    get '/'
    assert(last_response.body =~ %r|<script|, "response body should include RUM auto instrumentation js:\n #{last_response.body}")
    assert(last_response.body =~ %r|NREUMQ|, "response body should include RUM auto instrumentation js:\n #{last_response.body}")
  end

  def test_autoinstrumentation_with_basic_page_puts_header_at_beginning_of_head
    @inner_app.response = "<html><head><title>foo</title></head><body><p>Hello World</p></body></html>"
    NewRelic::Agent.logger.debug("================================")
    get '/'
    NewRelic::Agent.logger.debug("================================")
    assert(last_response.body.include?('<html><head><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script><title>foo</title></head><body>'))
  end

  def test_autoinstrumentation_with_body_only_puts_header_before_body
    @inner_app.response = "<html><body><p>Hello World</p></body></html>"
    get '/'
    assert(last_response.body.include?('<html><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script><body>'))
  end

  def test_autoinstrumentation_with_X_UA_Compatible_puts_header_after_meta_tag
    @inner_app.response = '<html><head><meta http-equiv="X-UA-Compatible" content="IE=8;FF=3;OtherUA=4" /></head><body><p>Hello World</p></body></html>'
    get '/'
    assert(last_response.body.include?(
      '<html><head><meta http-equiv="X-UA-Compatible" content="IE=8;FF=3;OtherUA=4" /><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script></head><body>'
    ))
  end

  def test_autoinstrumentation_doesnt_run_for_crazy_shit_like_this
    @inner_app.response = '<html><head <body </body>'
    get '/'
    assert_equal('<html><head <body </body>', last_response.body)
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
end
