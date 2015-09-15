# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/javascript_instrumentor"
require "base64"

class NewRelic::Agent::JavascriptInstrumentorTest < Minitest::Test
  attr_reader :instrumentor

  def setup
    @config = {
      :application_id         => '5, 6', # collector can return app multiple ids
      :beacon                 => 'beacon',
      :browser_key            => 'browserKey',
      :js_agent_loader        => 'loader',
      :license_key            => "\0",  # no-op obfuscation key
      :'rum.enabled'          => true,
      :disable_harvest_thread => true
    }
    NewRelic::Agent.config.add_config_for_testing(@config)

    events = stub(:subscribe => nil)
    @instrumentor = NewRelic::Agent::JavascriptInstrumentor.new(events)

    # By default we expect our transaction to have a start time
    # All sorts of basics don't output without this setup initially
    NewRelic::Agent::TransactionState.tl_get.reset
  end

  def teardown
    NewRelic::Agent::TransactionState.tl_clear_for_testing
    NewRelic::Agent.config.reset_to_defaults
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

  def test_browser_timing_header_outside_transaction
    assert_equal "", instrumentor.browser_timing_header
  end

  def test_browser_timing_scripts_with_rum_enabled_false
    with_config(:'rum.enabled' => false) do
      in_transaction do
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
    with_config(:js_agent_loader => '') do
      in_transaction do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_without_beacon
    with_config(:beacon => '') do
      in_transaction do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_without_browser_key
    with_config(:browser_key => '') do
      in_transaction do
        assert_equal "", instrumentor.browser_timing_header
      end
    end
  end

  def test_browser_timing_header_with_ignored_enduser
    in_transaction do |txn|
      txn.ignore_enduser!
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

  def test_browser_timing_header_safe_when_insert_js_fails
    in_transaction do
      begin
        NewRelic::Agent.stubs(:config).raises("Hahahaha")
        assert_equal "", instrumentor.browser_timing_header
      ensure
        # stopping the transaction touches config, so we need to ensure we
        # clean up after ourselves here.
        NewRelic::Agent.unstub(:config)
      end
    end
  end

  def test_browser_timing_header_safe_when_loader_generation_fails
    in_transaction do
      instrumentor.stubs(:html_safe_if_needed).raises("Hahahaha")
      assert_equal "", instrumentor.browser_timing_header
    end
  end

  def test_browser_timing_header_safe_when_json_dump_fails
    in_transaction do
      NewRelic::JSONWrapper.stubs(:dump).raises("Serialize? Hahahaha")
      assert_equal "", instrumentor.browser_timing_header
    end
  end

  def test_config_data_for_js_agent
    freeze_time
    with_config(CAPTURE_ATTRIBUTES => true) do
      in_transaction('most recent transaction') do
        txn = NewRelic::Agent::Transaction.tl_current
        txn.stubs(:queue_time).returns(0)
        txn.stubs(:start_time).returns(Time.now - 10)
        txn.stubs(:guid).returns('ABC')

        state = NewRelic::Agent::TransactionState.tl_get

        data = instrumentor.data_for_js_agent(state)
        expected = {
          "beacon"          => "beacon",
          "errorBeacon"     => "",
          "licenseKey"      => "browserKey",
          "applicationID"   => "5, 6",
          "transactionName" => pack("most recent transaction"),
          "queueTime"       => 0,
          "applicationTime" => 10000,
          "agent"           => ""
        }

        js = instrumentor.browser_timing_config(state)
        expected.each do |key, value|
          assert_equal(value, data[key])
          assert_match(/"#{key.to_s}":#{formatted_for_matching(value)}/, js)
        end
      end
    end
  end

  def test_config_data_for_js_agent_attributes
    freeze_time
    with_config(CAPTURE_ATTRIBUTES => true) do
      in_transaction('most recent transaction') do
        NewRelic::Agent.add_custom_attributes(:user => "user")
        NewRelic::Agent::Transaction.add_agent_attribute(:agent, "attribute", NewRelic::Agent::AttributeFilter::DST_ALL)

        state = NewRelic::Agent::TransactionState.tl_get
        data = instrumentor.data_for_js_agent(state)

        # Handle packed atts key specially since it's obfuscated
        actual = unpack_to_object(data["atts"])
        expected = {
          "u" => {"user" => "user"},
          "a" => {"agent" => "attribute"}
        }
        assert_equal expected, actual
      end
    end
  end

  def test_ssl_for_http_not_included_by_default
    state = NewRelic::Agent::TransactionState.tl_get
    data = instrumentor.data_for_js_agent(state)
    assert_not_includes data, "sslForHttp"
  end

  def test_ssl_for_http_enabled
    with_config(:'browser_monitoring.ssl_for_http' => true) do
      state = NewRelic::Agent::TransactionState.tl_get
      data = instrumentor.data_for_js_agent(state)
      assert data["sslForHttp"]
    end
  end

  def test_ssl_for_http_disabled
    with_config(:'browser_monitoring.ssl_for_http' => false) do
      state = NewRelic::Agent::TransactionState.tl_get
      data = instrumentor.data_for_js_agent(state)
      assert_false data["sslForHttp"]
    end
  end

  ATTRIBUTES_ENABLED = :'browser_monitoring.attributes.enabled'
  CAPTURE_ATTRIBUTES = :'browser_monitoring.capture_attributes'

  def test_data_for_js_agent_doesnt_get_custom_attributes_by_default
    with_config({}) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes({:boo => "hoo"})
        assert_attributes_missing
      end
    end
  end

  def test_data_for_js_agent_doesnt_get_custom_attributes_outside_transaction
    with_config(CAPTURE_ATTRIBUTES => true) do
      NewRelic::Agent.add_custom_attributes({:boo => "hoo"})
      assert_attributes_missing
    end
  end


  def test_data_for_js_agent_gets_custom_attributes_with_old_config
    with_config(CAPTURE_ATTRIBUTES => true) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes({:boo => "hoo"})
        assert_attributes_are('{"u":{"boo":"hoo"}}')
      end
    end
  end

  def test_data_for_js_agent_gets_custom_attributes_when_configured
    with_config(ATTRIBUTES_ENABLED => true) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes({:boo => "hoo"})
        assert_attributes_are('{"u":{"boo":"hoo"}}')
      end
    end
  end

  def test_data_for_js_agent_ignores_custom_attributes_by_config
    with_config(CAPTURE_ATTRIBUTES => false) do
      in_transaction do
        NewRelic::Agent.add_custom_attributes({:boo => "hoo"})
        assert_attributes_missing
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

  def assert_attributes_are(expected)
    state = NewRelic::Agent::TransactionState.tl_get
    data = instrumentor.data_for_js_agent(state)
    assert_equal pack(expected), data["atts"]
  end

  def assert_attributes_missing
    state = NewRelic::Agent::TransactionState.tl_get
    data = instrumentor.data_for_js_agent(state)
    assert_not_includes data, "atts"
  end

  def pack(text)
    [text].pack("m0").gsub("\n", "")
  end

  def unpack_to_object(text)
    unpacked_atts = instrumentor.obfuscator.deobfuscate(text)
    NewRelic::JSONWrapper.load(unpacked_atts)
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
