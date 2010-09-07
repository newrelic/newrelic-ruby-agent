# Run faster standalone
# ENV['SKIP_RAILS'] = 'true'
require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', 'test_helper'))
require 'rack'

class EpisodesTest < Test::Unit::TestCase
  
  def setup
    super
    
    @app = Mocha::Mockery.instance.named_mock 'Episodes'
    #@app = mock('Episodes')
    @e = NewRelic::Rack::Episodes.new(@app)
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
    @agent.transaction_sampler.send :clear_builder
    @agent.transaction_sampler.reset!
    @agent.stats_engine.clear_stats
  end
  
  def test_match
    @e.expects(:process).times(3)
    @app.expects(:call).times(2)
    @e.call(mock_env('/newrelic/episodes/page_load/stuff'))    
    @e.call(mock_env('/newrelic/episodes/page_load'))
    @e.call(mock_env('/newrelic/episodes/page_load?'))
    
    @e.call(mock_env('/v2/newrelic/episodes/page_load?'))
    @e.call(mock_env('/v2'))
  end
  
  def test_process
    
    args = "ets=backend:2807,onload:7641,frontend:4835,pageready:7642,totaltime:7642&" +
           "url=/bogosity/bogus_action&"+
           "userAgent=#{Rack::Utils.escape("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2.2) Gecko/20100316 Firefox/3.6.2")}"
    v = @e.call(mock_env("/newrelic/episodes/page_load?#{args}"))
    assert_equal 3, v.size
    assert_equal 204, v[0]
    compare_metrics %w[
      Apdex/Client/4.4
      Apdex/Client/4.4/Mac/Firefox/3.6
      Client/totaltime
      Client/frontend
      Client/backend
      Client/onload
      Client/pageready
      Client/totaltime/Mac/Firefox/3.6
      Client/frontend/Mac/Firefox/3.6
      Client/backend/Mac/Firefox/3.6
      Client/onload/Mac/Firefox/3.6
      Client/pageready/Mac/Firefox/3.6],  @agent.stats_engine.metrics 
    totaltime = @agent.stats_engine.get_stats_no_scope('Client/totaltime')
    assert_equal 1, totaltime.call_count
    assert_equal 7.642, totaltime.average_call_time
    totaltime = @agent.stats_engine.get_stats_no_scope('Client/totaltime/Mac/Firefox/3.6')
    assert_equal 1, totaltime.call_count
    assert_equal 7.642, totaltime.average_call_time
  end
  
  context "when normalizing user agent strings" do
    setup do
      setup
      @e.class.send :public, :identify_browser_and_os
    end
    
    should "parse 'like Firefox/* Gecko/*' as Gecko" do
      browser, version, os = @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC; en-US; rv:1.0rc2) Gecko/20020512 like Firefox/3.1")
      
      assert_equal "Mozilla Gecko", browser
      assert_equal 1.0, version
    end
    
    should "parse 'Chrome/' as Chrome, unknown version" do
      browser, version, os = @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_6; en-US) AppleWebKit/530.5 (KHTML, like Gecko) Chrome/ Safari/530.5")
      
      assert_equal "Chrome", browser
      assert_equal 0, version
    end
    
    should "parse x.y float versions for Firefox, Gecko and Webkit" do
    browser, version, os = @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; ru; rv:1.9.2) Gecko/20100105 Firefox/3.6")
    assert Float === version
    
    browser, version, os = @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC; en-US; rv:1.0rc2) Gecko/20020512 Netscape/7.0b1")
    assert Float === version
    
    browser, version, os = @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_5_2; en-gb) AppleWebKit/526+ (KHTML, like Gecko) Version/3.1 iPhone")
    assert Float === version
  end
  
  context "in-the-wild" do
    should "identify AOL correctly" do
      assert_equal ["IE", 5, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 5.5; AOL 6.0; Windows 98)"), "AOL 6.0 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; AOL 6.0; Windows NT 5.1)"), "AOL 6.0 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; AOL 7.0; Windows 98; SpamBlockerUtility 4.8.0)"), "AOL 7.0 identified incorrectly"
      assert_equal ["IE", 7, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 7.0; AOL 7.0; Windows NT 5.1; .NET CLR 1.1.4322)"), "AOL 7.0 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; AOL 8.0; Windows NT 5.1)"), "AOL 8.0 identified incorrectly"
      assert_equal ["IE", 7, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 7.0; AOL 8.0; Windows NT 5.1; GTB5; .NET CLR 1.1.4322; .NET CLR 2.0.50727)"), "AOL 8.0 identified incorrectly"
      assert_equal ["IE", 8, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 8.0; AOL 9.5; AOLBuild 4337.29; Windows NT 6.0; Trident/4.0; SLCC1; .NET CLR 2.0.50727; Media Center PC 5.0; .NET CLR 3.5.21022; .NET CLR 3.5.30729; .NET CLR 3.0.30618)"), "AOL 9.5 identified incorrectly"
    end
    
    should "identify Camino correctly" do
      assert_equal ["Mozilla Gecko", 1.8, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en-US; rv:1.8.0.1) Gecko/20060214 Camino/1.0"), "Camino 1.0 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.8.0.1) Gecko/20060119 Camino/1.0b2+"), "Camino 1.0b2+ identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en; rv:1.8.1.4) Gecko/20070509 Camino/1.5"), "Camino 1.5 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en; rv:1.9.0.18) Gecko/2010021619 Camino/2.0.2 (like Firefox/3.0.18)"), "Camino 2.0.2 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en; rv:1.9.0.10pre) Gecko/2009041800 Camino/2.0b3pre (like Firefox/3.0.10pre)"), "Camino 2.0b3pre identified incorrectly"
    end
    
    should "identify Chrome correctly" do
      assert_equal ["Chrome", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_6; en-US) AppleWebKit/530.5 (KHTML, like Gecko) Chrome/ Safari/530.5"), "Chrome  identified incorrectly"
      assert_equal ["Chrome", 1, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.2; en-US) AppleWebKit/525.19 (KHTML, like Gecko) Chrome/1.0.154.59 Safari/525.19"), "Chrome 1.0.154.59 identified incorrectly"
      assert_equal ["Chrome", 2, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/528.8 (KHTML, like Gecko) Chrome/2.0.156.0 Version/3.2.1 Safari/528.8"), "Chrome 2.0.156.0 identified incorrectly"
      assert_equal ["Chrome", 2, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686 (x86_64); en-US) AppleWebKit/530.7 (KHTML, like Gecko) Chrome/2.0.175.0 Safari/530.7"), "Chrome 2.0.175.0 identified incorrectly"
      assert_equal ["Chrome", 3, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-US) AppleWebKit/531.3 (KHTML, like Gecko) Chrome/3.0.192 Safari/531.3"), "Chrome 3.0.192 identified incorrectly"
      assert_equal ["Chrome", 3, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; en-US) AppleWebKit/531.3 (KHTML, like Gecko) Chrome/3.0.193.0 Safari/531.3"), "Chrome 3.0.193.0 identified incorrectly"
      assert_equal ["Chrome", 3, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US) AppleWebKit/531.4 (KHTML, like Gecko) Chrome/3.0.194.0 Safari/531.4"), "Chrome 3.0.194.0 identified incorrectly"
      assert_equal ["Chrome", 3, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/532.0 (KHTML,like Gecko) Chrome/3.0.195.27"), "Chrome 3.0.195.27 identified incorrectly"
      assert_equal ["Chrome", 4, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/532.0 (KHTML, like Gecko) Chrome/4.0.201.1 Safari/532.0"), "Chrome 4.0.201.1 identified incorrectly"
      assert_equal ["Chrome", 4, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US) AppleWebKit/532.0 (KHTML, like Gecko) Chrome/4.0.202.0 Safari/532.0"), "Chrome 4.0.202.0 identified incorrectly"
      assert_equal ["Chrome", 4, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_6; en-US) AppleWebKit/532.0 (KHTML, like Gecko) Chrome/4.0.202.0 Safari/532.0"), "Chrome 4.0.202.0 identified incorrectly"
      assert_equal ["Chrome", 4, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0 (x86_64); de-DE) AppleWebKit/532.0 (KHTML, like Gecko) Chrome/4.0.202.2 Safari/532.0"), "Chrome 4.0.202.2 identified incorrectly"
      assert_equal ["Chrome", 5, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/532.9 (KHTML, like Gecko) Chrome/5.0.307.1 Safari/532.9"), "Chrome 5.0.307.1 identified incorrectly"
      assert_equal ["Chrome", 5, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_0; en-US) AppleWebKit/532.9 (KHTML, like Gecko) Chrome/5.0.307.11 Safari/532.9"), "Chrome 5.0.307.11 identified incorrectly"
      assert_equal ["Chrome", 5, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/532.9 (KHTML, like Gecko) Chrome/5.0.309.0 Safari/532.9"), "Chrome 5.0.309.0 identified incorrectly"
      assert_equal ["Chrome", 6, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.2 (KHTML, like Gecko) Chrome/6.0"), "Chrome 6.0 identified incorrectly"
    end
    
    should "identify Fennec correctly" do # Mozilla mobile browser
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux armv6l; en-US; rv:1.9.1a1pre) Gecko/2008071707 Fennec/0.5"), "Fennec 0.5 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux armv6l; en-US; rv:1.9.1a2pre) Gecko/20080820121708 Fennec/0.7"), "Fennec 0.7 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux armv6l; en-US; rv:1.9.1b1pre) Gecko/20080923171103 Fennec/0.8"), "Fennec 0.8 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux armv6l; en-US; rv:1.9.1b1pre) Gecko/20081005220218 Gecko/2008052201 Fennec/0.9pre"), "Fennec 0.9pre identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.2a1pre) Gecko/20090626 Fennec/1.0b2"), "Fennec 1.0b2 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux armv7l; en-US; rv:1.9.2a1pre) Gecko/20090322 Fennec/1.0b2pre"), "Fennec 1.0b2pre identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Win98; en-US; rv:1.8.1.17) Gecko/20080829 Mozilla/5.0 (X11; U; Linux armv7l; en-US; rv:1.9.2a1pre) Gecko/20090322 Fennec/1.0b2pre"), "Fennec 1.0b2pre identified incorrectly"
    end
    
    should "identify Firefox correctly" do
      assert_equal ["Firefox", 1.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.2; de-DE; rv:1.7.6) Gecko/20050321 Firefox/1.0.2"), "Firefox 1.0.2 identified incorrectly"
      assert_equal ["Firefox", 1.5, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; lt-LT; rv:1.6) Gecko/20051114 Firefox/1.5"), "Firefox 1.5 identified incorrectly"
      assert_equal ["Firefox", 1.5, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows NT 5.2; U; de; rv:1.8.0) Gecko/20060728 Firefox/1.5.0"), "Firefox 1.5.0 identified incorrectly"
      assert_equal ["Firefox", 1.5, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.8.0.9) Gecko/20070126 Ubuntu/dapper-security Firefox/1.5.0.9"), "Firefox 1.5.0.9 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11;U;Linux i686;en-US;rv:1.8.1) Gecko/2006101022 Firefox/2.0"), "Firefox 2.0 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; PPC Mac OS X; U; en; rv:1.8.1) Gecko/20061208 Firefox/2.0.0"), "Firefox 2.0.0 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows NT 6.0; U; hu; rv:1.8.1) Gecko/20061208 Firefox/2.0.0"), "Firefox 2.0.0 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.2; en-GB; rv:1.8.1.13) Gecko/20080311 Firefox/2.0.0.13"), "Firefox 2.0.0.13 identified incorrectly"
      assert_equal ["Firefox", 3.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.8) Gecko/2009032609 Firefox/3.0.0 (.NET CLR 3.5.30729)"), "Firefox 3.0.0 identified incorrectly"
      assert_equal ["Firefox", 3.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; tr-TR; rv:1.9.0.10) Gecko/2009042523 Ubuntu/9.04 (jaunty) Firefox/3.0.10"), "Firefox 3.0.10 identified incorrectly"
      assert_equal ["Firefox", 3.5, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; ru; rv:1.9.1) Gecko/20090624 Firefox/3.5 (.NET CLR 3.5.30729)"), "Firefox 3.5 identified incorrectly"
      assert_equal ["Firefox", 3.5, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; fr; rv:1.9.1b4) Gecko/20090423 Firefox/3.5b4"), "Firefox 3.5b4 identified incorrectly"
      assert_equal ["Firefox", 3.6, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; ru; rv:1.9.2) Gecko/20100105 Firefox/3.6 (.NET CLR 3.5.30729)"), "Firefox 3.6 identified incorrectly"
      assert_equal ["Firefox", 3.6, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2.2) Gecko/20100316 Firefox/3.6.2"), "Firefox 3.6.2 identified incorrectly"
    end
    
    should "identify Flock correctly" do
      assert_equal ["Firefox", 2.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.17) Gecko/20080910 Firefox/2.0.0.17 Flock/1.2.6"), "Flock 1.2.6 identified incorrectly"
      assert_equal ["Firefox", 3.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.0.3) Gecko/2008100716 Firefox/3.0.3 Flock/2.0"), "Flock 2.0 identified incorrectly"
      assert_equal ["Firefox", 3.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.3) Gecko/2008100719 Firefox/3.0.3 Flock/2.0"), "Flock 2.0 identified incorrectly"
      assert_equal ["Safari", 0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.1.7) Gecko/20091221 AppleWebKit/531.21.8 KHTML/4.3.2 (like Gecko) Firefox/3.5.7 Flock/2.5.6 (.NET CLR 3.5.30729)"), "Flock 2.5.6 identified incorrectly"
    end
    
    should "identify Fluid correctly" do # Safari-based single-site browser
      assert_equal ["Safari", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_1; nl-nl) AppleWebKit/532.3+ (KHTML, like Gecko) Fluid/0.9.6 Safari/532.3+"), "Fluid 0.9.6 identified incorrectly"
    end
    
    should "identify Iceweasel correctly" do # Debian's Firefox
      assert_equal ["Firefox", 1.5, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.0.8pre) Gecko/20061001 Firefox/1.5.0.8pre (Iceweasel)"), "Iceweasel  identified incorrectly"
      assert_equal ["Firefox", 3.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-GB; rv:1.9.0.7) Gecko/2009030814 Iceweasel Firefox/3.0.7 (Debian-3.0.7-1)"), "Iceweasel  identified incorrectly"
      assert_equal ["Firefox", 2.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.1.13) Gecko/20080311 Firefox/2.0 Iceweasel/2.0.0.3 (Debian-2.0.0.13-1)"), "Iceweasel 2.0.0.3 identified incorrectly"
    end
    
    should "identify IE correctly" do
      assert_equal ["IE", 3, "Windows"], @e.identify_browser_and_os("Mozilla/3.0 (compatible; MSIE 3.0; Windows NT 5.0)"), "Internet Explorer 3.0 identified incorrectly"
      assert_equal ["IE", 4, "Windows"], @e.identify_browser_and_os("Mozilla/2.0 (compatible; MSIE 4.0; Windows 98)"), "Internet Explorer 4.0 identified incorrectly"
      assert_equal ["IE", 4, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 4.01; Windows CE)"), "Internet Explorer 4.01 identified incorrectly"
      assert_equal ["IE", 4, "Unknown"], @e.identify_browser_and_os(" Mozilla/4.0 (compatible; MSIE 4.5; Mac_PowerPC)"), "Internet Explorer 4.5 identified incorrectly"
      assert_equal ["IE", 4, "Unknown"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 4.5; Mac_PowerPC)"), "Internet Explorer 4.5 identified incorrectly"
      assert_equal ["IE", 5, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 5.0; Windows NT; DigExt; .NET CLR 1.0.3705)"), "Internet Explorer 5.00 identified incorrectly"
      assert_equal ["IE", 5, "Unknown"], @e.identify_browser_and_os(" Mozilla/4.0 (compatible; MSIE 5.2; Mac_PowerPC)"), "Internet Explorer 5.2 identified incorrectly"
      assert_equal ["IE", 5, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.1; .NET CLR 2.0.50727)"), "Internet Explorer 5.50 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.08 (compatible; MSIE 6.0; Windows NT 5.1)"), "Internet Explorer 6.0 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (Compatible; Windows NT 5.1; MSIE 6.0) (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.1.4322; .NET CLR 2.0.50727)"), "Internet Explorer 6.0 identified incorrectly"
      assert_equal ["IE", 6, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.1; Windows XP)"), "Internet Explorer 6.1 identified incorrectly"
      assert_equal ["IE", 7, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (Mozilla/4.0; MSIE 7.0; Windows NT 5.1; FDM; SV1; .NET CLR 3.0.04506.30)"), "Internet Explorer 7.0 identified incorrectly"
      assert_equal ["IE", 7, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (compatible; MSIE 7.0; Windows NT 6.0; SLCC1; .NET CLR 2.0.50727; Media Center PC 5.0; c .NET CLR 3.0.04506; .NET CLR 3.5.30707; InfoPath.1; el-GR)"), "Internet Explorer 7.0 identified incorrectly"
      assert_equal ["IE", 8, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; GTB6.4; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; MSSDMC2.5.2219.1)"), "Internet Explorer 8.0 identified incorrectly"
      assert_equal ["IE", 8, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; Media Center PC 6.0; InfoPath.2; MS-RTC LM 8)"), "Internet Explorer 8.0 identified incorrectly"
      assert_equal ["IE", 8, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.2; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0)"), "Internet Explorer 8.0 identified incorrectly"
    end
    
    should "identify Mozilla correctly" do
      assert_equal ["Mozilla Gecko", 1.4, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.4) Gecko/20030908 Debian/1.4-4"), "Mozilla 1.4 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.4, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.4) Gecko/20030624"), "Mozilla 1.4 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.5, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; de-AT; rv:1.5) Gecko/20031007"), "Mozilla 1.5 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.5, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.0; de-AT; rv:1.5) Gecko/20031007"), "Mozilla 1.5 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.6, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux x86_64; fr; rv:1.6) Gecko/20040115"), "Mozilla 1.6 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.6, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.6) Gecko/20040113"), "Mozilla 1.6 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.6, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.0; de-AT; rv:1.6) Gecko/20040113"), "Mozilla 1.6 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.6, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; fr-FR; rv:1.6) Gecko/20040113"), "Mozilla 1.6 identified incorrectly"
      
      # no way to tell that this string isn't Firefox, so let's lump it into Firefox
      assert_equal ["Firefox", 0.9, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; es-ES; rv:1.7) Gecko/20040803 Firefox/0.9.3"), "Mozilla 1.7 identified incorrectly"
      
      assert_equal ["Mozilla Gecko", 1.7, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7) Gecko/20040514"), "Mozilla 1.7 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.7, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.7) Gecko/20040616"), "Mozilla 1.7 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.0.5) Gecko/20060719 KHTML/3.5.5"), "Mozilla 1.8.0.5 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en-US; rv:1.8.1.11) Gecko/20071206"), "Mozilla 1.8.1.11 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.1.13) Gecko/20080313"), "Mozilla 1.8.1.13 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.0; en-US; rv:1.9.2a1pre) Gecko"), "Mozilla 1.9.2a1pre identified incorrectly"
      
      assert_equal ["Mozilla Gecko", 0.9, "Linux"], @e.identify_browser_and_os(" Mozilla/5.0 (X11; U; Linux i686; en-US; rv:0.9.2) Gecko/20010726 Netscape6/6.1"), "Netscape 6.1 identified incorrectly"
      assert_equal ["Mozilla Gecko", 0.9, "Mac"], @e.identify_browser_and_os(" Mozilla/5.0 (Macintosh; U; PPC; de-DE; rv:0.9.2) Gecko/20010726 Netscape6/6.1"), "Netscape 6.1 identified incorrectly"
      assert_equal ["Mozilla Gecko", 0.9, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; fr-FR; rv:0.9.2) Gecko/20010726 Netscape6/6.1"), "Netscape 6.1 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.0; ja-JP; rv:1.0.2) Gecko/20021120 Netscape/7.01"), "Netscape 7.01 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.0rc2) Gecko/20020513 Netscape/7.0b1"), "Netscape 7.0b1 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC; en-US; rv:1.0rc2) Gecko/20020512 Netscape/7.0b1"), "Netscape 7.0b1 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.7, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.7.5) Gecko/20060111 Netscape/8.1"), "Netscape 8.1 identified incorrectly"
      
      # no way to tell that these aren't Firefox
      assert_equal ["Firefox", 2.0, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.1.8pre) Gecko/20071015 Firefox/2.0.0.7 Navigator/9.0"), "Netscape 9.0 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.8.1.8pre) Gecko/20071015 Firefox/2.0.0.7 Navigator/9.0"), "Netscape 9.0 identified incorrectly"
      assert_equal ["Firefox", 2.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Win 9x 4.90; en-US; rv:1.8.1.8pre) Gecko/20071015 Firefox/2.0.0.7 Navigator/9.0"), "Netscape 9.0 identified incorrectly"
    end
    
    should "identify OmniWeb correctly" do
      assert_equal ["Safari", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en-US) AppleWebKit/125.4 (KHTML, like Gecko, Safari) OmniWeb/v563.59"), "OmniWeb v563.59 identified incorrectly"
    end
    
    should "identify Opera correctly" do
      assert_equal ["Opera", 0, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; en) Opera"), "Opera  identified incorrectly"
      assert_equal ["Opera", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; ; Intel Mac OS X; fr; rv:1.8.1.1) Gecko/20061204 Opera"), "Opera  identified incorrectly"
      assert_equal ["Opera", 7, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; MSIE 5.5; Windows XP) Opera 7.0 [en]"), "Opera 7.0 identified incorrectly"
      assert_equal ["Opera", 7, "Windows"], @e.identify_browser_and_os("Mozilla/4.78 (Windows NT 5.0; U) Opera 7.01 [en]"), "Opera 7.01 identified incorrectly"
      assert_equal ["Opera", 7, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows NT 5.0; U) Opera 7.01 [en]"), "Opera 7.01 identified incorrectly"
      assert_equal ["Opera", 7, "Windows"], @e.identify_browser_and_os("Opera/7.52 (Windows NT 5.1; U) [en]"), "Opera 7.52 identified incorrectly"
      assert_equal ["Opera", 7, "Linux"], @e.identify_browser_and_os("Opera/7.53 (X11; Linux i686; U) [en_US]"), "Opera 7.53 identified incorrectly"
      assert_equal ["Opera", 8, "Linux"], @e.identify_browser_and_os("Opera/8.0 (X11; Linux i686; U; cs)"), "Opera 8.00 identified incorrectly"
      assert_equal ["Opera", 8, "Windows"], @e.identify_browser_and_os("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; ru) Opera 8.0"), "Opera 8.00 identified incorrectly"
      assert_equal ["Opera", 9, "Mac"], @e.identify_browser_and_os("Opera/9.01 (Macintosh; PPC Mac OS X; U; en)"), "Opera 9.01 identified incorrectly"
      assert_equal ["Opera", 9, "Linux"], @e.identify_browser_and_os("Opera/9.02 (X11; Linux i686; U; pl)"), "Opera 9.02 identified incorrectly"
      assert_equal ["Opera", 9, "Windows"], @e.identify_browser_and_os("Opera/9.02 (Windows NT 5.0; U; de)"), "Opera 9.02 identified incorrectly"
      assert_equal ["Opera", 9, "Linux"], @e.identify_browser_and_os("Opera/9.64 (X11; Linux x86_64; U; pl) Presto/2.1.1"), "Opera 9.64 identified incorrectly"
      assert_equal ["Opera", 9, "Windows"], @e.identify_browser_and_os("Opera/9.64 (Windows NT 6.0; U; pl) Presto/2.1.1"), "Opera 9.64 identified incorrectly"
      assert_equal ["Opera", 10, "Linux"], @e.identify_browser_and_os("Opera/9.80 (X11; Linux x86_64; U; en) Presto/2.2.15 Version/10.00"), "Opera 10.00 identified incorrectly"
      assert_equal ["Opera", 10, "Windows"], @e.identify_browser_and_os("Opera/9.80 (Windows NT 5.1; U; ru) Presto/2.2.15 Version/10.00"), "Opera 10.00 identified incorrectly"
    end
    
    should "identify Safari correctly" do
      assert_equal ["Safari", 0, "iPhone"], @e.identify_browser_and_os("Mozilla/5.0 (iPod; U; CPU iPhone OS 2_2_1 like Mac OS X; en-us) AppleWebKit/525.18.1 (KHTML, like Gecko) Mobile/5H11"), "Safari  identified incorrectly"
      assert_equal ["Safari", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/125.2 (KHTML, like Gecko) Safari/125.7"), "Safari 1.2.2 identified incorrectly"
      assert_equal ["Safari", 0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X; es) AppleWebKit/417.9 (KHTML, like Gecko) Safari/417.8"), "Safari 2.0.3 identified incorrectly"
      assert_equal ["Safari", 3.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; nl) AppleWebKit/522.11.3 (KHTML, like Gecko) Version/3.0 Safari/522.11.3"), "Safari 3.0 identified incorrectly"
      assert_equal ["Safari", 3.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; pl-PL) AppleWebKit/523.12.9 (KHTML, like Gecko) Version/3.0 Safari/523.12.9"), "Safari 3.0 identified incorrectly"
      assert_equal ["Safari", 3.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X; de-de) AppleWebKit/522.11.1 (KHTML, like Gecko) Version/3.0.3 Safari/522.12.1"), "Safari 3.0.3 identified incorrectly"
      assert_equal ["Safari", 3.1, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.2; ru-RU) AppleWebKit/525.13 (KHTML, like Gecko) Version/3.1 Safari/525.13.3"), "Safari 3.1 identified incorrectly"
      assert_equal ["Safari", 3.1, "iPhone"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_5_2; en-gb) AppleWebKit/526+ (KHTML, like Gecko) Version/3.1 iPhone"), "Safari 3.1 identified incorrectly"
      assert_equal ["Safari", 3.1, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_2; fr-fr) AppleWebKit/525.18 (KHTML, like Gecko) Version/3.1.1 Safari/525.18"), "Safari 3.1.1 identified incorrectly"
      assert_equal ["Safari", 4.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; ja-JP) AppleWebKit/528.16 (KHTML, like Gecko) Version/4.0 Safari/528.16"), "Safari 4.0 identified incorrectly"
      assert_equal ["Safari", 4.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.19.2 (KHTML, like Gecko) Version/4.0.1 Safari/530.18"), "Safari 4.0.1 identified incorrectly"
      assert_equal ["Safari", 4.0, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_3; en-us) AppleWebKit/531.22.7 (KHTML, like Gecko) Version/4.0.5 Safari/531.22.7"), "Safari 4.0.5 identified incorrectly"
      assert_equal ["Safari", 4.0, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.0; en-US) AppleWebKit/531.22.7 (KHTML, like Gecko) Version/4.0.5 Safari/531.22.7"), "Safari 4.0.5 identified incorrectly"
    end
    
    should "identify SeaMonkey correctly" do # Mozilla distribution of core Gecko engine
      assert_equal ["Mozilla Gecko", 1.8, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux i686; de-AT; rv:1.8.1.5) Gecko/20070716 SeaMonkey/1.1.3"), "SeaMonkey 1.1.3 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.8, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 5.1; es-ES; rv:1.8.1.5) Gecko/20070716 SeaMonkey/1.1.3"), "SeaMonkey 1.1.3 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Windows"], @e.identify_browser_and_os("Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US; rv:1.9.1b3pre) Gecko/20081208 SeaMonkey/2.0"), "SeaMonkey 2.0 identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Linux"], @e.identify_browser_and_os("Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.9.1.9pre) Gecko/20100212 SeaMonkey/2.0.4pre"), "SeaMonkey 2.0.4pre identified incorrectly"
      assert_equal ["Mozilla Gecko", 1.9, "Mac"], @e.identify_browser_and_os("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.4; en-US; rv:1.9.1b3pre) Gecko/20090223 SeaMonkey/2.0a3"), "SeaMonkey 2.0a3 identified incorrectly"
    end
  end
end

private

def mock_env(uri_override)
  path, query = uri_override.split('?')
  
  Hash[
         'HTTP_ACCEPT'                  => 'application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
         'HTTP_ACCEPT_ENCODING'         => 'gzip, deflate',
         'HTTP_ACCEPT_LANGUAGE'         => 'en-us',
         'HTTP_CACHE_CONTROL'           => 'max-age=0',
         'HTTP_CONNECTION'              => 'keep-alive',
         'HTTP_COOKIE'                  => '_newrelic_development_session=BAh7CzoPc2Vzc2lvbl9pZCIlMTlkMGE5MTY1YmNhNTM5MjAxODRiNjdmNWY3ZTczOTU6D2FjY291bnRfaWRpBjoMdXNlcl9pZGkGOhNhcHBsaWNhdGlvbl9pZCIGMyIKZmxhc2hJQzonQWN0aW9uQ29udHJvbGxlcjo6Rmxhc2g6OkZsYXNoSGFzaHsABjoKQHVzZWR7ADoQdGltZV93aW5kb3dvOg9UaW1lV2luZG93CjoQQGJlZ2luX3RpbWVJdToJVGltZQ3OixuAAAAAGAY6H0BtYXJzaGFsX3dpdGhfdXRjX2NvZXJjaW9uRjoWQHJlcG9ydGluZ19wZXJpb2RpQToOQGVuZF90aW1lSXU7Dg3RixuAAAAAGAY7D0Y6DkBlbmRzX25vd1Q6D0ByYW5nZV9rZXk6EUxBU1RfM19IT1VSUw%3D%3D--ac863fb87fc0233caa5063398300a9b4c0c1fe71; _newrelic_local_production_session=BAh7CjoPc2Vzc2lvbl9pZCIlMjFmOGQzMmMwZmUxYjYzMjcyYjU1NzBkYmMyNzA5NTc6DHVzZXJfaWRpHjoTYXBwbGljYXRpb25faWQiCTE3NDY6D2FjY291bnRfaWRpPiIKZmxhc2hJQzonQWN0aW9uQ29udHJvbGxlcjo6Rmxhc2g6OkZsYXNoSGFzaHsABjoKQHVzZWR7AA%3D%3D--22ebf9e965e67d49430d8b9c2817302b37628766; auth_token=d0bf9b0468c3b994b23a0e1cdc712824ab4246d9',
         'HTTP_HOST'                    => 'localhost:3000',
         'HTTP_USER_AGENT'              => 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; en-us) AppleWebKit/531.22.7 (KHTML, like Gecko) Version/4.0.5 Safari/531.22.7',
         'HTTP_VERSION'                 => 'HTTP/1.1',
         'QUERY_STRING'                 => query,
         'REMOTE_ADDR'                  => '127.0.0.1',
         'REQUEST_METHOD'               => 'GET',
         'PATH_INFO'                    => path,
         'REQUEST_PATH'                 => path,
         'REQUEST_URI'                  => uri_override,
         'SCRIPT_NAME'                  => '',
         'SERVER_NAME'                  => 'localhost',
         'SERVER_PORT'                  => '3000',
         'SERVER_PROTOCOL'              => 'HTTP/1.1',
         'SERVER_SOFTWARE'              => 'Unicorn 0.97.0',
         'rack.input'                   => StringIO.new,
         'rack.errorst'                 => StringIO.new,
  #         'rack.logger'                  => '#<Logger:0x1014d7cc0>',
  #         'rack.session.options'         => 'path/key_session_idexpire_afterdomainhttponlytrue',
         'rack.multiprocess'            => 'true',
         'rack.multithread'             => 'false',
         'rack.run_once'                => 'false',
         'rack.session'                 => '',
         'rack.url_scheme'              => 'http',
         'rack.version'                 => '11'
  ]
end

def mock_routes
  ActionController::Routing::Routes.nil;
end
end if defined? NewRelic::Rack::Episodes
