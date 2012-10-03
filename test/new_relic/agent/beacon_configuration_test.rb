require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/beacon_configuration"
class NewRelic::Agent::BeaconConfigurationTest < Test::Unit::TestCase
  def test_initialize_basic
    with_config(:application_id => 'an application id',
                :beacon => 'beacon', :'rum.enabled' => true) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert_equal true, bc.enabled?
      assert_equal '', bc.browser_timing_header
    end
  end

  def test_initialize_with_real_data
    with_config(:browser_key => 'a key', :application_id => 'an application id',
                :beacon => 'beacon', :'rum.enabled' => true) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert bc.enabled?
      s = "<script type=\"text/javascript\">var NREUMQ=NREUMQ||[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);</script>"
      assert_equal(s, bc.browser_timing_header)
    end
  end

  def test_license_bytes_nil
    with_config(:license_key => 'a' * 40) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert_equal([97] * 40, bc.license_bytes, 'should return the bytes of the license key')
    end
  end

  def test_license_bytes_existing_bytes
    bc = NewRelic::Agent::BeaconConfiguration.new
    bc.instance_eval { @license_bytes = [97] * 40 }
    NewRelic::Agent.config.expects(:[]).with('license_key').never
    assert_equal([97] * 40, bc.license_bytes, "should return the cached value if it exists")
  end

  def test_license_bytes_should_set_instance_cache
    with_config(:license_key => 'a' * 40) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      bc.instance_eval { @license_bytes = nil }
      bc.license_bytes
      assert_equal([97] * 40, bc.instance_variable_get('@license_bytes'), "should cache the license bytes for later")
    end
  end

  def test_build_browser_timing_header_disabled
    bc = NewRelic::Agent::BeaconConfiguration.new
    bc.instance_eval { @rum_enabled = false }
    assert_equal '', bc.build_browser_timing_header, "should not return a header when rum enabled is false"
  end

  def test_build_browser_timing_header_enabled_but_no_key
    bc = NewRelic::Agent::BeaconConfiguration.new
    bc.instance_eval { @rum_enabled = true; @browser_monitoring_key = nil }
    assert_equal '', bc.build_browser_timing_header, "should not return a header when browser_monitoring_key is nil"
  end

  def test_build_browser_timing_header_enabled_with_key
    with_config(:browser_key => 'a browser monitoring key', :beacon => 'beacon') do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert(bc.build_browser_timing_header.include?('NREUMQ'),
             "header should be generated when rum is enabled and browser monitoring key is set")
    end
  end

  def test_build_browser_timing_header_should_html_safe_header
    with_config(:browser_key => 'a' * 40, :beacon => 'beacon') do
      mock_javascript = mock('javascript')
      bc = NewRelic::Agent::BeaconConfiguration.new
      bc.expects(:javascript_header).returns(mock_javascript)
      mock_javascript.expects(:respond_to?).with(:html_safe).returns(true)
      mock_javascript.expects(:html_safe)
      bc.build_browser_timing_header
    end
  end

  def test_build_load_file_js_load_episodes_file_false
    with_config(:'rum.load_episodes_file' => false) do
      bc = NewRelic::Agent::BeaconConfiguration.new
      s = "if (!NREUMQ.f) { NREUMQ.f=function() {\nNREUMQ.push([\"load\",new Date().getTime()]);\nif(NREUMQ.a)NREUMQ.a();\n};\nNREUMQ.a=window.onload;window.onload=NREUMQ.f;\n};\n"
      assert_equal(s, bc.build_load_file_js)
    end
  end

  def test_build_load_file_js_load_episodes_file_missing
    with_config(:'rum.load_episodes_file' => '') do
      bc = NewRelic::Agent::BeaconConfiguration.new
      s = "if (!NREUMQ.f) { NREUMQ.f=function() {\nNREUMQ.push([\"load\",new Date().getTime()]);\nif(NREUMQ.a)NREUMQ.a();\n};\nNREUMQ.a=window.onload;window.onload=NREUMQ.f;\n};\n"
      assert_equal(s, bc.build_load_file_js)
    end
  end

  def test_build_load_file_js_load_episodes_file_present
    bc = NewRelic::Agent::BeaconConfiguration.new
#     s = "if (!NREUMQ.f) { NREUMQ.f=function() {\nNREUMQ.push([\"load\",new Date().getTime()]);\nvar e=document.createElement(\"script\");\ne.type=\"text/javascript\";e.async=true;e.src=\"\";\ndocument.body.appendChild(e);\nif(NREUMQ.a)NREUMQ.a();\n};\nNREUMQ.a=window.onload;window.onload=NREUMQ.f;\n};\n"
    s = "if (!NREUMQ.f) { NREUMQ.f=function() {\nNREUMQ.push([\"load\",new Date().getTime()]);\nvar e=document.createElement(\"script\");\ne.type=\"text/javascript\";\ne.src=((\"http:\"===document.location.protocol)?\"http:\":\"https:\") + \"//\" +\n  \"\";\ndocument.body.appendChild(e);\nif(NREUMQ.a)NREUMQ.a();\n};\nNREUMQ.a=window.onload;window.onload=NREUMQ.f;\n};\n"
    assert_equal(s, bc.build_load_file_js)
  end

  def test_build_load_file_js_load_episodes_file_with_episodes_file
    with_config(:episodes_file => 'an episodes url') do
      bc = NewRelic::Agent::BeaconConfiguration.new
      assert(bc.build_load_file_js.include?('an episodes url'),
             "should include the episodes url by default")
    end
  end
end
