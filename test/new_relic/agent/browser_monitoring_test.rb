ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/browser_monitoring"

class NewRelic::Agent::BrowserMonitoringTest < Test::Unit::TestCase
  include NewRelic::Agent::BrowserMonitoring

  def setup
    @browser_monitoring_key = "fred"
    @episodes_file = "this_is_my_file"
    NewRelic::Agent.instance.instance_eval do
      @beacon_configuration = NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => true, "browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"})
    end
  end

  def teardown
    mocha_teardown
    Thread.current[:newrelic_start_time] = nil
    Thread.current[:newrelic_metric_frame] = nil
  end

 # def test_browser_timing_short_header_not_execution_traced
 #   header = nil
 #   NewRelic::Agent.disable_all_tracing do
 #    header = browser_timing_short_header
 #   end
 #   assert_equal "", header
 # end

  def test_browser_timing_header_with_no_beacon_configuration
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( nil)
    header = browser_timing_header
    assert_equal "", header
    end
    
  def test_browser_timing_header
    header = browser_timing_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
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

  #def test_browser_timing_header_not_execution_traced
  #   header = nil
  #   NewRelic::Agent.disable_all_tracing do
  #     header = browser_timing_header
  #   end
  #   assert_equal "", header
  # end

  def test_browser_timing_footer
    NewRelic::Control.instance.expects(:license_key).returns("a" * 13)

    Thread.current[:newrelic_start_time] = Time.now

    footer = browser_timing_footer
    assert footer.include?("<script type=\"text/javascript\" charset=\"utf-8\">NREUMQ.push([\"nrf2\",")
  end

  def test_browser_timing_footer_with_no_browser_key_rum_enabled
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => true, "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    footer = browser_timing_footer
    assert_equal "", footer
  end
  
  def test_browser_timing_footer_with_no_browser_key_deux
     NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"rum.enabled" => false, "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
     footer = browser_timing_footer
     assert_equal "", footer
   end
  
  def test_browser_timing_footer_with_rum_enabled_not_specified
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
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( nil)
    footer = browser_timing_footer
    assert_equal "", footer
  end

  def test_browser_timing_footer_with_no_start_time
    Thread.current[:newrelic_start_time] = nil
    NewRelic::Agent.instance.expects(:beacon_configuration).returns( NewRelic::Agent::BeaconConfiguration.new({"browser_key" => "browserKey", "application_id" => "apId", "beacon"=>"beacon", "episodes_url"=>"this_is_my_file"}))
    footer = browser_timing_footer
    assert_equal('', footer)
  end
    

 # def test_browser_timing_footer_not_execution_traced
 #   footer = nil
 #   NewRelic::Agent.disable_all_tracing do
    
 #       Thread.current[:newrelic_untraced] = [false]
 #   puts Thread.current[:newrelic_untraced].last
 #     footer = browser_timing_footer
 #   end
 #   assert_equal "", footer
 # end
end
