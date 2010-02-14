require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

class NewRelic::Agent::MemcacheInstrumentationTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  # This implementation: http://seattlerb.rubyforge.org/memcache-client/
  def using_memcache_client?
    ::MemCache.method_defined? :cache_get
  end

  def setup
    NewRelic::Agent.manual_start
    @engine = NewRelic::Agent.instance.stats_engine
    
    if using_memcache_client?
      @cache = ::MemCache.new('localhost')
    else
      server = ::MemCache::Server.new('localhost')
      @cache = ::MemCache.new(server)
    end
    @key = 'schluessel'
    @task = 'task'
  end

  def _call_test_method_in_web_transaction(method, *args)
    @engine.clear_stats
    begin
      perform_action_with_newrelic_trace(@task) do
        @cache.send(method.to_sym, *[@key, *args])
      end
    rescue ::MemCache::MemCacheError
      # There's probably no memcached around
    end
  end

  def _call_test_method_in_background_task(method, *args)
    @engine.clear_stats
    begin
      perform_action_with_newrelic_trace(@task, :category => :task) do
        @cache.send(method.to_sym, *[@key, *args])
      end
    rescue ::MemCache::MemCacheError
      # There's probably no memcached around
    end
  end

  def test_reads__web
    %w[get get_multi].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        assert_equal ["MemCache/read", "MemCache/allWeb", "MemCache/read:Controller/NewRelic::Agent::MemcacheInstrumentationTest/#{@task}"].sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end
  end
  
  def test_writes__web
    expected_metrics = ["MemCache/write", "MemCache/allWeb", "MemCache/write:Controller/NewRelic::Agent::MemcacheInstrumentationTest/#{@task}"]

    %w[incr decr delete].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method)
        assert_equal expected_metrics.sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end

    %w[set add].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_web_transaction(method, 'value')
        assert_equal expected_metrics.sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end
  end

  def test_reads__background
    %w[get get_multi].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        assert_equal ["MemCache/read", "MemCache/allOther", "MemCache/read:OtherTransaction/Background/NewRelic::Agent::MemcacheInstrumentationTest/#{@task}"].sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end
  end

  def test_writes__background
    expected_metrics = ["MemCache/write", "MemCache/allOther", "MemCache/write:OtherTransaction/Background/NewRelic::Agent::MemcacheInstrumentationTest/#{@task}"]

    %w[incr decr delete].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method)
        assert_equal expected_metrics.sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end

    %w[set add].each do |method|
      if @cache.class.method_defined?(method)
        _call_test_method_in_background_task(method, 'value')
        assert_equal expected_metrics.sort, @engine.metrics.select{|m| m =~ /^memcache.*/i}.sort, "Failed on method #{method}"
      end
    end
  end

end if defined? MemCache
