# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

begin
  require 'rack/test'
rescue LoadError
  nil
end

if defined?(::Rack::Test)
  require_relative '../../test_helper'
  require 'new_relic/rack/browser_monitoring'

  ENV['RACK_ENV'] = 'test'

  class BrowserMonitoringTest < Minitest::Test
    include Rack::Test::Methods

    class TestApp
      @@doc = nil
      @@next_response = nil

      def self.doc=(other)
        @@doc = other
      end

      def self.next_response=(next_response)
        @@next_response = next_response
      end

      def self.next_response
        @@next_response
      end

      def call(env)
        advance_process_time(0.1)
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
        response = @@next_response || Rack::Response.new(@@doc)
        @@next_response = nil

        [200, {'Content-Type' => 'text/html'}, response]
      end
    end

    def app
      NewRelic::Rack::BrowserMonitoring.new(TestApp.new)
    end

    def setup
      super
      nr_freeze_process_time

      @config = {
        :application_id => 5,
        :beacon => 'beacon',
        :browser_key => 'some browser key',
        :'rum.enabled' => true,
        :license_key => 'a' * 40,
        :js_agent_loader => 'loader',
        :disable_harvest_thread => true
      }
      NewRelic::Agent.config.add_config_for_testing(@config)
    end

    def teardown
      super
      TestApp.doc = nil
      NewRelic::Agent.config.remove_config(@config)
      NewRelic::Agent.agent.transaction_sampler.reset!
    end

    def test_make_sure_header_is_set
      in_transaction do
        assert NewRelic::Agent.browser_timing_header.size > 0
      end
    end

    def test_should_only_instrument_successful_html_requests
      assert app.should_instrument?({}, 200, {'Content-Type' => 'text/html'}), "Expected to instrument 200 requests."
      refute app.should_instrument?({}, 500, {'Content-Type' => 'text/html'}), "Expected not to instrument 500 requests."
      refute app.should_instrument?({}, 200, {'Content-Type' => 'text/xhtml'}), "Expected not to instrument requests with content type other than text/html."
    end

    def test_should_not_instrument_when_content_disposition
      refute app.should_instrument?({}, 200, {'Content-Type' => 'text/html', 'Content-Disposition' => 'attachment; filename=test.html'})
    end

    def test_should_not_instrument_when_already_did
      refute app.should_instrument?({NewRelic::Rack::BrowserMonitoring::ALREADY_INSTRUMENTED_KEY => true}, 200, {'Content-Type' => 'text/html'})
    end

    def test_should_not_instrument_when_disabled_by_config
      with_config(:'browser_monitoring.auto_instrument' => false) do
        refute app.should_instrument?({}, 200, {'Content-Type' => 'text/html'})
      end
    end

    def test_should_not_inject_javascript_when_transaction_ignored
      with_config(:'rules.ignore_url_regexes' => ['^/ignore/path']) do
        get('/ignore/path')

        app.stubs(:should_instrument?).returns(true)
        app.expects(:autoinstrument_source).never
      end
    end

    def test_insert_header_should_mark_environment
      get('/')

      assert last_request.env.key?(NewRelic::Rack::BrowserMonitoring::ALREADY_INSTRUMENTED_KEY)
    end

    # RUM header auto-insertion testing
    # We read *.html files from the rum_loader_insertion_location directory in
    # cross_agent_tests, strip out the placeholder tokens representing the RUM
    # header manually, and then re-insert, verifying that it ends up in the right
    # place.

    source_files = Dir[File.join(cross_agent_tests_dir, 'rum_loader_insertion_location', "*.html")]

    RUM_PLACEHOLDER = "EXPECTED_RUM_LOADER_LOCATION"

    source_files.each do |source_file|
      source_filename = File.basename(source_file).tr(".", "_")
      instrumented_html = File.read(source_file)
      uninstrumented_html = instrumented_html.gsub(RUM_PLACEHOLDER, '')

      define_method("test_#{source_filename}") do
        TestApp.doc = uninstrumented_html
        NewRelic::Agent.stubs(:browser_timing_header).returns(RUM_PLACEHOLDER)

        get '/'

        assert_equal(instrumented_html, last_response.body)
      end

      define_method("test_dont_touch_#{source_filename}") do
        TestApp.doc = uninstrumented_html
        NewRelic::Rack::BrowserMonitoring.any_instance.stubs(:should_instrument?).returns(false)

        get '/'

        assert_equal(uninstrumented_html, last_response.body)
      end
    end

    def test_should_close_response
      TestApp.next_response = Rack::Response.new("<html/>")
      TestApp.next_response.expects(:close)

      get('/')

      assert_predicate last_response, :ok?
    end

    def test_with_invalid_us_ascii_encoding
      response = String.new('<html><body>Jürgen</body></html>')
      response.force_encoding(Encoding.find("US-ASCII"))
      TestApp.next_response = Rack::Response.new(response)

      get('/')

      assert_predicate last_response, :ok?
    end

    def test_should_not_close_if_not_responded_to
      TestApp.next_response = Rack::Response.new("<html/>")
      TestApp.next_response.stubs(:respond_to?).with(:close).returns(false)
      TestApp.next_response.expects(:close).never

      get('/')

      assert_predicate last_response, :ok?
    end

    def test_should_not_throw_exception_on_empty_response
      TestApp.doc = ''
      get('/')

      assert_predicate last_response, :ok?
    end

    def test_content_length_set_when_we_modify_source
      original_headers = {
        "Content-Length" => "0",
        "Content-Type" => "text/html"
      }
      headers = headers_from_request(original_headers, "<html><body></body></html>")

      assert_equal "390", headers["Content-Length"]
    end

    def test_content_length_set_when_we_modify_source_containing_unicode
      original_headers = {
        "Content-Length" => "0",
        "Content-Type" => "text/html"
      }
      headers = headers_from_request(original_headers, "<html><body>☃</body></html>")

      assert_equal "393", headers["Content-Length"]
    end

    def test_content_length_set_when_response_is_nil
      original_headers = {
        "Content-Length" => "0",
        "Content-Type" => "text/html"
      }
      headers = headers_from_request(original_headers, nil)

      assert_equal "0", headers["Content-Length"]
    end

    def headers_from_request(headers, content)
      content = Array(content) if content

      app = mock('app', :call => [200, headers, content])
      browser_monitoring = NewRelic::Rack::BrowserMonitoring.new(app)
      _, headers, _ = browser_monitoring.call({})
      headers
    end
  end
else
  puts "Skipping tests in #{__FILE__} because Rack::Test is unavailable"
end
