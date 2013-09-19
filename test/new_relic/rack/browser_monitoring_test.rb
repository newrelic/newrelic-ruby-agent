# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..',
                                   'test_helper'))
require 'rack/test'
require 'new_relic/agent/instrumentation/rack'
require 'new_relic/rack/browser_monitoring'

ENV['RACK_ENV'] = 'test'

# we should expand the environments we support, any rack app could
# benefit from auto-rum, but the truth of the matter is that atm
# we only support Rails >= 2.3
def middleware_supported?
  defined?(::Rails) && ::Rails::VERSION::STRING >= '2.3'
end

if middleware_supported?
class BrowserMonitoringTest < Test::Unit::TestCase
  include Rack::Test::Methods

  class TestApp
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
    include NewRelic::Agent::Instrumentation::Rack
  end

  def app
    NewRelic::Rack::BrowserMonitoring.new(TestApp.new)
  end

  def setup
    super
    clear_cookies
    @config = {
      :browser_key => 'some browser key',
      :beacon => 'beacon',
      :application_id => 5,
      :'rum.enabled' => true,
      :episodes_file => 'this_is_my_file',
      :license_key => 'a' * 40
    }
    NewRelic::Agent.config.apply_config(@config)
    NewRelic::Agent.manual_start
    config = NewRelic::Agent::BeaconConfiguration.new
    NewRelic::Agent.instance.stubs(:beacon_configuration).returns(config)
    NewRelic::Agent.stubs(:is_transaction_traced?).returns(true)
  end

  def teardown
    super
    clear_cookies
    mocha_teardown
    TestApp.doc = nil
    NewRelic::Agent.config.remove_config(@config)
    NewRelic::Agent.agent.transaction_sampler.reset!
  end

  def test_make_sure_header_is_set
    assert NewRelic::Agent.browser_timing_header.size > 0
  end

  def test_make_sure_footer_is_set
    assert NewRelic::Agent.browser_timing_footer.size > 0
  end

  def test_should_only_instrument_successfull_html_requests
    assert app.should_instrument?({}, 200, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?({}, 500, {'Content-Type' => 'text/html'})
    assert !app.should_instrument?({}, 200, {'Content-Type' => 'text/xhtml'})
  end

  def test_should_not_instrument_when_content_disposition
    assert !app.should_instrument?({}, 200, {'Content-Type' => 'text/html', 'Content-Disposition' => 'attachment; filename=test.html'})
  end

  def test_should_not_instrument_when_already_did
    assert !app.should_instrument?({NewRelic::Rack::BrowserMonitoring::ALREADY_INSTRUMENTED_KEY => true}, 200, {'Content-Type' => 'text/html'})
  end

  def test_insert_header_should_mark_environment
    get '/'
    assert last_request.env.key?(NewRelic::Rack::BrowserMonitoring::ALREADY_INSTRUMENTED_KEY)
  end

  # RUM header auto-insertion testing
  # We read *.source.html files from the test/rum directory, and then
  # compare the results of them to *.result.html files.

  source_files = Dir[File.join(File.dirname(__FILE__), "..", "..", "rum", "*.source.html")]

  RUM_HEADER = "|||I AM THE RUM HEADER|||"
  RUM_FOOTER = "|||I AM THE RUM FOOTER|||"

  source_files.each do |source_file|
    source_filename = File.basename(source_file).gsub(".", "_")
    source_html = File.read(source_file)

    result_file = source_file.gsub(".source.", ".result.")

    define_method("test_#{source_filename}") do
      TestApp.doc = source_html
      NewRelic::Agent.instance.stubs(:browser_timing_header).returns(RUM_HEADER)
      NewRelic::Agent.instance.stubs(:browser_timing_footer).returns(RUM_FOOTER)

      get '/'

      expected_content = File.read(result_file)
      assert_equal(expected_content, last_response.body)
    end

    define_method("test_dont_touch_#{source_filename}") do
      TestApp.doc = source_html
      NewRelic::Rack::BrowserMonitoring.any_instance.stubs(:should_instrument?).returns(false)

      get '/'

      assert_equal(source_html, last_response.body)
    end
  end

  def test_should_not_throw_exception_on_empty_reponse
    TestApp.doc = ''
    get '/'

    assert last_response.ok?
  end

  def test_token_is_set_in_footer_when_set_by_cookie
    token = '1234567890987654321'
    set_cookie "NRAGENT=tk=#{token}"
    get '/'

    assert(last_response.body.include?(token), last_response.body)
  end

  def test_guid_is_set_in_footer_when_token_is_set
    guid = 'abcdefgfedcba'
    NewRelic::TransactionSample.any_instance.stubs(:generate_guid).returns(guid)
    set_cookie "NRAGENT=tk=token"
    with_config(:apdex_t => 0.0001) do
      get '/'
      assert(last_response.body.include?(guid), last_response.body)
    end
  end

  def test_calculate_content_length_accounts_for_multibyte_characters_for_186
    String.stubs(:respond_to?).with(:bytesize).returns(false)
    browser_monitoring = NewRelic::Rack::BrowserMonitoring.new(mock('app'))
    assert_equal 24, browser_monitoring.calculate_content_length("猿も木から落ちる")
  end

  def test_calculate_content_length_accounts_for_multibyte_characters_for_modern_ruby
    browser_monitoring = NewRelic::Rack::BrowserMonitoring.new(mock('app'))
    assert_equal 18, browser_monitoring.calculate_content_length("七転び八起き")
  end
end
else
  puts "Skipping tests in #{__FILE__} because Rails is unavailable (or too old)"
end
