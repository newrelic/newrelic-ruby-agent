require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/rack/browser_monitoring'

ENV['RACK_ENV'] = 'test'

class BrowserMonitoringTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  class TestApp
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    
    def self.doc=(other)
      @@doc = other
    end

    def call(env)
      @@doc ||= <<-EOL
<html>
  <head>
    <title>im a title</title>
    <meta some-crap="1"/>
    <script>
      junk
    </script>
  </head>
  <body>im some body text</body>
</html>
EOL
      [200, {'Content-Type' => 'text/html'}, Rack::Response.new(@@doc)]
    end
    add_transaction_tracer :call, :category => :rack    
  end
  
  def app
    NewRelic::Rack::BrowserMonitoring.new(TestApp.new)
  end
  
  def setup
    super
    clear_cookies
    NewRelic::Agent.manual_start
    config = NewRelic::Agent::BeaconConfiguration.new("browser_key" => "browserKey",
                                                      "application_id" => "apId",
                                                      "beacon"=>"beacon",
                                                      "episodes_url"=>"this_is_my_file")
    NewRelic::Agent.instance.stubs(:beacon_configuration).returns(config)
    NewRelic::Agent.stubs(:is_transaction_traced?).returns(true)
  end
  
  def teardown
    super
    clear_cookies
    mocha_teardown
    TestApp.doc = nil
  end
  
  def test_make_sure_header_is_set
    assert NewRelic::Agent.browser_timing_header.size > 0
  end
  
  def test_make_sure_footer_is_set
    assert NewRelic::Agent.browser_timing_footer.size > 0
  end
  
  def test_should_only_instrument_successfull_html_requests
    assert app.should_instrument?(200, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(500, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?(200, {'Content-Type' => 'text/xhtml'})
  end

  def test_insert_timing_header_right_after_open_head_if_no_meta_tags
    get '/'
    
    assert(last_response.body.include?("head>#{NewRelic::Agent.browser_timing_header}"),
           last_response.body)
    TestApp.doc = nil
  end  
  
  def test_insert_timing_header_right_before_head_close_if_ua_compatible_found
    TestApp.doc = <<-EOL
<html>
  <head>
    <title>im a title</title>
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"/>
    <script>
      junk
    </script>
  </head>
  <body>im some body text</body>
</html>
EOL
    get '/'
    
    assert(last_response.body.include?("#{NewRelic::Agent.browser_timing_header}</head>"),
           last_response.body)
  end
  
  def test_insert_timing_footer_right_before_html_body_close
    get '/'
    
    assert(last_response.body.include?("#{NewRelic::Agent.browser_timing_footer}</body>"),
           last_response.body)
  end
  
  def test_should_not_throw_exception_on_empty_reponse
    TestApp.doc = ''
    get '/'

    assert last_response.ok?
  end
  
  def test_transaction_token_is_in_footer_when_set_by_cookie
    transaction_token = '1234567890987654321'
    set_cookie "NRAGENT=tk=#{transaction_token}"
    get '/'

    assert(last_response.body.include?(transaction_token), last_response.body)
  end
end
