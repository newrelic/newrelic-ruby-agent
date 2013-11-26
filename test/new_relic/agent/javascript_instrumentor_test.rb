# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/javascript_instrumentor"
require "base64"

class NewRelic::Agent::JavascriptInstrumentorTest < Test::Unit::TestCase
  attr_reader :instrumentor

  def setup
    @config = {
      :application_id         => '5, 6', # collector can return app multiple ids
      :beacon                 => 'beacon',
      :browser_key            => 'browserKey',
      :js_agent_loader        => 'loader',
      :license_key            => "\0",  # no-op obfuscation key
      :'rum.enabled'          => true
    }
    NewRelic::Agent.config.apply_config(@config)

    events = stub(:subscribe => nil)
    @instrumentor = NewRelic::Agent::JavascriptInstrumentor.new(events)

    # By default we expect our transaction to have a start time
    # All sorts of basics don't output without this setup initially
    NewRelic::Agent::TransactionState.reset(nil)
  end

  def teardown
    NewRelic::Agent::TransactionState.clear
    NewRelic::Agent.config.remove_config(@config)
  end

  def test_js_errors_beta_default_gets_default_loader
    assert_equal "rum", NewRelic::Agent.config[:'browser_monitoring.loader']
  end

  def test_js_errors_beta_gets_full_loader
    with_config(:js_errors_beta => true) do
      assert_equal "full", NewRelic::Agent.config[:'browser_monitoring.loader']
    end
  end

  def test_js_errors_beta_off_gets_default_loader
    with_config(:js_errors_beta => false) do
      assert_equal "rum", NewRelic::Agent.config[:'browser_monitoring.loader']
    end
  end

  def test_auto_instrumentation_config_defaults_to_enabled
    assert NewRelic::Agent.config[:'browser_monitoring.auto_instrument']
  end

  def test_start_time_reset_each_request_when_auto_instrument_is_disabled
    controller = Object.new
    def controller.perform_action_without_newrelic_trace(method, options={});
      # noop; instrument me
    end
    def controller.newrelic_metric_path; "foo"; end
    controller.extend ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

    with_config(:'browser_monitoring.auto_instrument' => false) do
      controller.perform_action_with_newrelic_trace(:index)
      first_request_start_time = instrumentor.current_transaction.start_time

      controller.perform_action_with_newrelic_trace(:index)
      second_request_start_time = instrumentor.current_transaction.start_time

      # assert that these aren't the same time object
      # the start time should be reinitialized each request to the controller
      assert !(first_request_start_time.equal? second_request_start_time)
    end
  end

  def test_browser_timing_header_outside_transaction
    assert_equal "", instrumentor.browser_timing_header
  end

  def test_browser_timing_scripts_with_rum_enabled_false
    in_transaction do
      with_config(:'rum.enabled' => false) do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_disable_transaction_tracing
    in_transaction do
      NewRelic::Agent.disable_transaction_tracing do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_disable_all_tracing
    in_transaction do
      NewRelic::Agent.disable_all_tracing do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_without_loader
    in_transaction do
      with_config(:js_agent_loader => '') do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_without_beacon
    in_transaction do
      with_config(:beacon => '') do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_without_browser_key
    in_transaction do
      with_config(:browser_key => '') do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_with_ignored_enduser
    in_transaction do
      NewRelic::Agent::TransactionState.get.request_ignore_enduser = true
      assert_equal "", instrumentor.browser_timing_header
    end
  end

  def test_browser_timing_header_with_default_settings
    in_transaction do
      header = instrumentor.browser_timing_header
      assert_has_js_agent_loader(header)
      assert_has_text(BEGINNING_OF_FOOTER, header)
      assert_has_text(END_OF_FOOTER, header)
    end
  end

  def test_data_for_js_agent_extra_parameter
    in_transaction do
      with_config(CAPTURE_ATTRIBUTES_PAGE_EVENTS => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_equal({:boo => "hoo"}, instrumentor.data_for_js_agent_extra_parameter)
      end
    end
  end

  def test_data_for_js_agent_extra_parameter_outside_transaction
    with_config(CAPTURE_ATTRIBUTES_PAGE_EVENTS => true) do
      NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
      assert_empty instrumentor.data_for_js_agent_extra_parameter
    end
  end

  def test_format
    assert_formatted({:a => "1", "b" => 2}, "a=1", "b=#2")
  end

  def test_format_extra_data_escaping
    assert_formatted({"semi;colon" => "gets;escaped"}, "semi:colon=gets:escaped")
    assert_formatted({"equal=key" => "equal=value"}, "equal-key=equal-value")
    assert_formatted({'"quoted"' => '"marks"'}, %Q['quoted'='marks'])
  end

  def test_format_extra_data_disallowed_types
    assert_formatted_empty({"nested" => { "hashes?" => "nope" }})
    assert_formatted_empty({"lists" => ["are", "they", "allowed?", "nope"]})
  end

  def assert_formatted(data, *expected)
    result = instrumentor.format_extra_data(data).split(";")
    expected.each do |expect|
      assert_includes(result, expect)
    end
  end

  def assert_formatted_empty(data)
    result = instrumentor.format_extra_data(data)
    assert_equal("", result)
  end

  def test_config_data_for_js_agent
    freeze_time
    in_transaction do
      with_config(CAPTURE_ATTRIBUTES_PAGE_EVENTS => true) do
        NewRelic::Agent.set_user_attributes(:user => "user")

        txn = NewRelic::Agent::Transaction.current
        txn.stubs(:queue_time).returns(0)
        txn.stubs(:start_time).returns(Time.now - 10)
        txn.name = 'most recent transaction'

        state = NewRelic::Agent::TransactionState.get
        state.request_token = '0123456789ABCDEF'
        state.request_guid = 'ABC'

        data = instrumentor.data_for_js_agent
        expected = {
          "beacon"          => "beacon",
          "errorBeacon"     => "",
          "licenseKey"      => "browserKey",
          "applicationID"   => "5, 6",
          "transactionName" => pack("most recent transaction"),
          "queueTime"       => 0,
          "applicationTime" => 10000,
          "ttGuid"          => "ABC",
          "agentToken"      => "0123456789ABCDEF",
          "agent"           => "",
          "extra"           => pack("user=user")
        }

        assert_equal(expected, data)

        js = instrumentor.browser_timing_config
        expected.each do |key, value|
          assert_match(/"#{key.to_s}":#{formatted_for_matching(value)}/, js)
        end
      end
    end
  end

  def test_ssl_for_http_not_included_by_default
    data = instrumentor.data_for_js_agent
    assert_false data.include?("sslForHttp")
  end

  def test_ssl_for_http_enabled
    with_config(:'browser_monitoring.ssl_for_http' => true) do
      data = instrumentor.data_for_js_agent
      assert data["sslForHttp"]
    end
  end

  def test_ssl_for_http_disabled
    with_config(:'browser_monitoring.ssl_for_http' => false) do
      data = instrumentor.data_for_js_agent
      assert_false data["sslForHttp"]
    end
  end

  ANALYTICS_ENABLED = :'analytics_events.enabled'
  CAPTURE_ATTRIBUTES_PAGE_EVENTS = :'capture_attributes.page_view_events'

  def test_data_for_js_agent_doesnt_pick_up_extras_by_default
    in_transaction do
      NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
      assert_extra_data_is("")
    end
  end

  def test_data_for_js_agent_picks_up_extras_when_configured
    in_transaction do
      with_config(ANALYTICS_ENABLED => true,
                  CAPTURE_ATTRIBUTES_PAGE_EVENTS => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("boo=hoo")
      end
    end
  end

  def test_data_for_js_agent_ignores_extras_if_no_analytics
    in_transaction do
      with_config(ANALYTICS_ENABLED => false,
                  CAPTURE_ATTRIBUTES_PAGE_EVENTS => true) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("")
      end
    end
  end

  def test_data_for_js_agent_ignores_extras_if_not_allowed_in_page
    in_transaction do
      with_config(ANALYTICS_ENABLED => true,
                  CAPTURE_ATTRIBUTES_PAGE_EVENTS => false) do
        NewRelic::Agent.add_custom_parameters({:boo => "hoo"})
        assert_extra_data_is("")
      end
    end
  end

  def test_html_safe_if_needed_unsafed
    string = mock('string')
    # here to handle 1.9 encoding - we stub this out because it should
    # be handled automatically and is outside the scope of this test
    string.stubs(:respond_to?).with(:encoding).returns(false)
    string.expects(:respond_to?).with(:html_safe).returns(false)
    assert_equal(string, instrumentor.html_safe_if_needed(string))
  end

  def test_html_safe_if_needed_safed
    string = mock('string')
    string.expects(:respond_to?).with(:html_safe).returns(true)
    string.expects(:html_safe).returns(string)
    # here to handle 1.9 encoding - we stub this out because it should
    # be handled automatically and is outside the scope of this test
    string.stubs(:respond_to?).with(:encoding).returns(false)
    assert_equal(string, instrumentor.html_safe_if_needed(string))
  end

  # Helpers

  BEGINNING_OF_FOOTER = '<script type="text/javascript">window.NREUM||(NREUM={});NREUM.info='
  END_OF_FOOTER = '}</script>'

  def assert_has_js_agent_loader(header)
    assert_match(%Q[\n<script type=\"text/javascript\">loader</script>],
                 header,
                 "expected new JS agent loader 'loader' but saw '#{header}'")
  end

  def assert_has_text(snippet, footer)
    assert(footer.include?(snippet), "Expected footer to include snippet: #{snippet}, but instead was #{footer}")
  end

  def assert_extra_data_is(expected)
    data = instrumentor.data_for_js_agent
    assert_equal pack(expected), data["extra"]
  end

  def pack(text)
    [text].pack("m0").gsub("\n", "")
  end

  def formatted_for_matching(value)
    case value
    when String
      %Q["#{value}"]
    when NilClass
      "null"
    else
      value
    end
  end

end
