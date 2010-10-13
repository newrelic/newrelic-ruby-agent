require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

memcached_ready = false
classes = {
  'memcache' => 'MemCache',
  'dalli' => 'Dalli::Client',
}
begin
  TCPSocket.new('localhost', 11211)
  classes.each do |req, const|
    begin
      require req
      MEMCACHED_CLASS = const.constantize
      puts "Testing #{MEMCACHED_CLASS}"
      memcached_ready = true
    rescue LoadError
    rescue NameError
    end
  end
rescue Errno::ECONNREFUSED
rescue Errno::ETIMEDOUT
end

class NewRelic::Agent::MemcacheInstrumentationTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent.instance.stats_engine
    
    @cache = MEMCACHED_CLASS.new('localhost')
    @cache.flush_all
    @key = 'schluessel'
  end
  
  def _call_test_method_in_web_transaction(method, *args)
    @engine.clear_stats
    perform_action_with_newrelic_trace(:name=>'action', :category => :controller) do
      @cache.send(method.to_sym, *[@key, *args])
    end
  end
  
  def _call_test_method_in_background_task(method, *args)
    @engine.clear_stats
    perform_action_with_newrelic_trace(:name => 'bg_task', :category => :task) do
      @cache.send(method.to_sym, *[@key, *args])
    end
  end
  
  def test_reads__web
    %w[get get_multi].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        compare_metrics ["MemCache/#{method}", "MemCache/allWeb", "MemCache/#{method}:Controller/NewRelic::Agent::MemcacheInstrumentationTest/action"],
        @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end
  
  def test_writes__web
    %w[incr decr delete].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        expected_metrics = ["MemCache/#{method}", "MemCache/allWeb", "MemCache/#{method}:Controller/NewRelic::Agent::MemcacheInstrumentationTest/action"]
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
    
    %w[set add].each do |method|
      if @cache.class.method_defined?(method)
        expected_metrics = ["MemCache/#{method}", "MemCache/allWeb", "MemCache/#{method}:Controller/NewRelic::Agent::MemcacheInstrumentationTest/action"]
        _call_test_method_in_web_transaction(method, 'value')
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end
  
  def test_reads__background
    %w[get get_multi].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        compare_metrics ["MemCache/#{method}", "MemCache/allOther", "MemCache/#{method}:OtherTransaction/Background/NewRelic::Agent::MemcacheInstrumentationTest/bg_task"],
        @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end
  
  def test_writes__background
    
    %w[incr decr delete].each do |method|
      expected_metrics = ["MemCache/#{method}", "MemCache/allOther", "MemCache/#{method}:OtherTransaction/Background/NewRelic::Agent::MemcacheInstrumentationTest/bg_task"]
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
    
    %w[set add].each do |method|
      expected_metrics = ["MemCache/#{method}", "MemCache/allOther", "MemCache/#{method}:OtherTransaction/Background/NewRelic::Agent::MemcacheInstrumentationTest/bg_task"]
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method, 'value')
        compare_metrics expected_metrics, @engine.metrics.select{|m| m =~ /^memcache.*/i}
      end
    end
  end
  
end if memcached_ready
