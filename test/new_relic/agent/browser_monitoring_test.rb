ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/browser_monitoring"

class NewRelic::Agent::BrowserMonitoringTest < Test::Unit::TestCase
  include NewRelic::Agent::BrowserMonitoring

  def setup
    NewRelic::Agent.manual_start
    @browser_monitoring_key = "fred"
    @episodes_file = "this_is_my_file"
    NewRelic::Agent.instance.instance_eval do
      @beacon_configuration = NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => true, "browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"})
    end
    Thread.current[:newrelic_most_recent_transaction] = {:scope_name => "MyCoolTransaction", :rum_header_added => false, :rum_footer_added => false}
  end

  def teardown
    mocha_teardown
    Thread.current[:newrelic_start_time] = nil
    Thread.current[:newrelic_metric_frame] = nil
    Thread.current[:newrelic_most_recent_transaction] = nil
  end

  def test_browser_timing_header_with_no_beacon_configuration
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( nil)
    header = browser_timing_header
    assert_equal "", header
    end

  def test_browser_timing_header
    header = browser_timing_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end
  
  def test_browser_timing_header_outside_transaction
    Thread.current[:newrelic_most_recent_transaction] = nil
    header = browser_timing_header
    assert_equal "", header
  end

  
  def test_browser_timing_header_twice
    header = browser_timing_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
    header = browser_timing_header
    assert_equal "", header
  end

  def test_browser_timing_header_with_rum_enabled_not_specified
    NewRelic::Agent.instance.expects(:beacon_configuration).at_least_once.returns( NewRelic::Agent::BeaconConfiguration.new({"browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    header = browser_timing_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end

  def test_browser_timing_header_with_rum_enabled_false
    NewRelic::Agent.instance.expects(:beacon_configuration).twice.returns( NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => false, "browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    header = browser_timing_header
    assert_equal "", header
  end

  def test_browser_timing_header_disable_all_tracing
     header = nil
     NewRelic::Agent.disable_all_tracing do
       header = browser_timing_header
     end
     assert_equal "", header
   end

  def test_browser_timing_header_disable_transaction_tracing
    header = nil
    NewRelic::Agent.disable_transaction_tracing do
      header = browser_timing_header
    end
    assert_equal "", header
  end

  def test_browser_timing_footer
    browser_timing_header
    NewRelic::Control.instance.expects(:license_key).returns("a" * 13)

    Thread.current[:newrelic_start_time] = Time.now

    footer = browser_timing_footer
    assert footer.include?("<script type=\"text/javascript\" charset=\"utf-8\">NREUMQ.push([\"nrf2\",")
  end
  
  def test_browser_timing_footer_outside_transaction
    Thread.current[:newrelic_most_recent_transaction] = nil
    footer = browser_timing_footer
    assert_equal "", footer
  end

  def test_browser_timing_footer_without_calling_header
    footer = browser_timing_footer
    assert_equal "", footer
  end
  
  def test_browser_timing_footer_twice
    browser_timing_header
    NewRelic::Control.instance.expects(:license_key).returns("a" * 13)

    Thread.current[:newrelic_start_time] = Time.now

    footer = browser_timing_footer
    assert footer.include?("<script type=\"text/javascript\" charset=\"utf-8\">NREUMQ.push([\"nrf2\",")

    footer = browser_timing_footer
    assert_equal "", footer
  end

  def test_browser_timing_footer_with_no_browser_key_rum_enabled
    browser_timing_header
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => true, "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    footer = browser_timing_footer
    assert_equal "", footer
  end

  def test_browser_timing_footer_with_no_browser_key_rum_disabled
    browser_timing_header
     NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => false, "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
     footer = browser_timing_footer
     assert_equal "", footer
   end

  def test_browser_timing_footer_with_rum_enabled_not_specified
    browser_timing_header
    Thread.current[:newrelic_start_time] = Time.now

    license_bytes = [];
    ("a" * 13).each_byte {|byte| license_bytes << byte}
    config =  NewRelic::Agent::BeaconConfiguration.new({"browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file", "license_bytes" => license_bytes})
    config.expects(:license_bytes).returns(license_bytes)
    NewRelic::Agent.instance.expects(:beacon_configuration).returns(config).at_least_once
    footer = browser_timing_footer
    assert footer.include?("<script type=\"text/javascript\" charset=\"utf-8\">NREUMQ.push([\"nrf2\",")
  end

  def test_browser_timing_footer_with_no_beacon_configuration
    browser_timing_header
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( nil)
    footer = browser_timing_footer
    assert_equal "", footer
  end

  def test_browser_timing_footer_with_no_start_time
    browser_timing_header
    Thread.current[:newrelic_start_time] = nil
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    footer = browser_timing_footer
    assert_equal('', footer)
  end


  def test_browser_timing_footer_disable_all_tracing
    browser_timing_header
    footer = nil
    NewRelic::Agent.disable_all_tracing do
      footer = browser_timing_footer
    end
    assert_equal "", footer
  end

  def test_browser_timing_footer_disable_transaction_tracing
    browser_timing_header
    footer = nil
    NewRelic::Agent.disable_transaction_tracing do
      footer = browser_timing_footer
    end
    assert_equal "", footer
  end
end
