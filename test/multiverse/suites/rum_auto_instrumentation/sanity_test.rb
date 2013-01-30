require 'test/unit'
require "rack/test"
require 'new_relic/rack/browser_monitoring'
require 'benchmark'

class MyApp
  # allow tests to set up the response they want.
  class << self
    def reset_headers
      @headers = {'Content-Type' => 'text/html'}
    end
    attr_accessor :response
    attr_accessor :headers
    def add_header(key, value)
      @headers[key] = value
      @headers
    end
  end



  def call(env)
    [200, self.class.headers, [self.class.response]]
  end
end

NewRelic::Agent.manual_start(:browser_key => 'browserKey', :application_id => 'appId',
                             :beacon => 'beacon', :episodes_file => 'this_is_my_file')
NewRelic::Agent.instance.instance_eval do
  @beacon_configuration = NewRelic::Agent::BeaconConfiguration.new
end

class RumAutoTest < Test::Unit::TestCase
  def setup
    MyApp.reset_headers
  end

  include Rack::Test::Methods

  def app
    NewRelic::Rack::BrowserMonitoring.new(MyApp.new)
  end


  def test_autoinstrumenation_is_active
    MyApp.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    get '/'
    assert(last_response.body =~ %r|<script|, "response body should include RUM auto instrumentation js:\n #{last_response.body}")
    assert(last_response.body =~ %r|NREUMQ|, "response body should include RUM auto instrumentation js:\n #{last_response.body}")
  end

  def test_autoinstrumenation_with_basic_page_puts_header_at_beggining_of_head
    MyApp.response = "<html><head><title>foo</title></head><body><p>Hello World</p></body></html>"
    get '/'
    assert(last_response.body.include?('<html><head><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script><title>foo</title></head><body>'))
  end

  def test_autoinstrumenation_with_body_only_puts_header_before_body
    MyApp.response = "<html><body><p>Hello World</p></body></html>"
    get '/'
    assert(last_response.body.include?('<html><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script><body>'))
  end

  def test_autoinstrumenation_with_X_UA_Compatible_puts_header_at_end_of_head
    MyApp.response = '<html><head><meta http-equiv="X-UA-Compatible" content="IE=8;FF=3;OtherUA=4" /></head><body><p>Hello World</p></body></html>'
    get '/'
    assert(last_response.body.include?(
      '<html><head><meta http-equiv="X-UA-Compatible" content="IE=8;FF=3;OtherUA=4" /><script type="text/javascript">var NREUMQ=NREUMQ||[];NREUMQ.push(["mark","firstbyte",new Date().getTime()]);</script></head><body>'
    ))
  end

  # regression
  def test_autoinstrumenation_fails_gracefully_with_X_UA_Compatible_and_no_close_head_tag_puts_header_before_body_tag
    MyApp.response = '<html><head><meta http-equiv="X-UA-Compatible" content="IE=8;FF=3;OtherUA=4" /><body><p>Hello World</p></body></html>'
    get '/'
    assert(!last_response.body.include?(%'NREUMQ'))
  end

  def test_autoinstrumenation_doesnt_run_for_crazy_shit_like_this
    MyApp.response = '<html><head <body </body>'
    get '/'
    assert_equal('<html><head <body </body>', last_response.body)
  end

  def test_content_length_is_correctly_set_if_present
    MyApp.response = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    content_length = MyApp.response.length
    MyApp.add_header("Content-Length", content_length)
    get '/'
    assert(last_response.headers['Content-Length'].to_i > content_length)
    assert_equal(last_response.body.length.to_s, last_response.headers['Content-Length'])
  end

  def test_xml_responses_arent_instrumented
    body = "<html><head><title>W00t!</title></head><body><p>Hello World</p></body></html>"
    MyApp.response = body
    MyApp.add_header("Content-Type", "text/xml")
    get '/'
    assert_equal(last_response.body, body)
  end
end

