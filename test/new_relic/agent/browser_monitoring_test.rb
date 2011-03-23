ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/browser_monitoring"

class NewRelic::Agent::BrowserMonitoringTest < Test::Unit::TestCase
  include NewRelic::Agent::BrowserMonitoring

  attr_reader :browser_monitoring_key
  attr_reader :episodes_file
  attr_reader :beacon
  attr_reader :license_key
  attr_reader :application_id
  attr_reader :obf
  attr_reader :queue_time
  attr_reader :app_time
    
  def setup
    @browser_monitoring_key = "fred"
    @episodes_file = "this_is_my_file"
  end

  def test_browser_timing_short_header_with_no_key
    @browser_monitoring_key = nil
    header = browser_timing_header(nil)
    assert_equal "", header
  end

  def test_browser_timing_short_header
    header = browser_timing_short_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()])</script>", header
  end
  
 # def test_browser_timing_short_header_not_execution_traced
 #   header = nil
 #   NewRelic::Agent.disable_all_tracing do
  #    header = browser_timing_short_header
 #   end
 #   assert_equal "", header
 # end

  def test_browser_timing_header_with_no_key
    @browser_monitoring_key = nil
    header = browser_timing_header(nil)
    assert_equal "", header
  end

  def test_browser_timing_header_with_nil
    header = browser_timing_header(nil)
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=((\"http:\"===d.location.protocol)?\"http:\":\"https:\")+\"//this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end

  def test_browser_timing_header
    header = browser_timing_header
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=((\"http:\"===d.location.protocol)?\"http:\":\"https:\")+\"//this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end
  
  #def test_browser_timing_header_not_execution_traced
  #   header = nil
  #   NewRelic::Agent.disable_all_tracing do
  #     header = browser_timing_header
  #   end
  #   assert_equal "", header
  # end

  def test_browser_timing_header_with_invalid_protocol
    header = browser_timing_header("crazy")
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"https://this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end

  def test_browser_timing_header_with_http
    header = browser_timing_header("http")
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"http://this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end

  def test_browser_timing_header_with_https
    header = browser_timing_header("https")
    assert_equal "<script>var NREUMQ=[];NREUMQ.push([\"mark\",\"firstbyte\",new Date().getTime()]);(function(){var d=document;var e=d.createElement(\"script\");e.type=\"text/javascript\";e.async=true;e.src=\"https://this_is_my_file\";var s=d.getElementsByTagName(\"script\")[0];s.parentNode.insertBefore(e,s);})()</script>", header
  end
  
  def test_browser_timing_footer
    NewRelic::Control.instance.expects(:license_key).returns("a" * 13)

    fake_metric_frame = mock("aFakeMetricFrame")
    fake_metric_frame.expects(:start).returns(Time.now).twice

    Thread.current[:newrelic_metric_frame] = fake_metric_frame

    footer = browser_timing_footer
    assert footer.include?("<script type=\"text/javascript\" charset=\"utf-8\">NREUMQ.push([\"nrf2\",")
  end

  def test_browser_timing_footer_with_no_key
    @browser_monitoring_key = nil
    footer = browser_timing_footer
    assert_equal "", footer
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