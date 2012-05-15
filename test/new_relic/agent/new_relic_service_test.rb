require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class NewRelicServiceTest < Test::Unit::TestCase
  def setup
    $fake_collector ||= NewRelic::FakeCollector.new
    $fake_collector.run
    $fake_collector.reset

    @server = NewRelic::Control::Server.new('127.0.0.1', 30303)    
    @service = NewRelic::Agent::NewRelicService.new('license-key', @server)
  end
  
  def test_connect_sets_agent_id_and_config_data
    $fake_collector.mock['connect']['config'] = 'some config directives'
    response = @service.connect
    assert_equal 1, response['agent_run_id']
    assert_equal 'some config directives', response['config']
  end

  def test_connect_sets_redirect_host
    assert_equal '127.0.0.1', @service.collector.name
    @service.connect    
    assert_equal 'localhost', @service.collector.name
  end

  def test_connect_uses_proxy_collector_if_no_redirect_host
    $fake_collector.mock['get_redirect_host'] = nil
    @service.connect
    assert_equal '127.0.0.1', @service.collector.name
  end

  def test_connect_sets_agent_id
    $fake_collector.mock['connect'] = {'agent_run_id' => 666}
    @service.connect
    assert_equal 666, @service.agent_id
  end

  def test_get_redirect_host
    response = @service.get_redirect_host
    assert_equal 'localhost', response
  end

  def test_shutdown
    $fake_collector.mock['shutdown'] = 'shut this bird down'
    response = @service.shutdown(Time.now)
    assert_equal 'shut this bird down', response
  end

  def test_metric_data
    $fake_collector.mock['metric_data'] = 'met rick date uhhh'
    response = @service.metric_data(Time.now - 60, Time.now, {})
    assert_equal 'met rick date uhhh', response
  end

  def test_error_data
    $fake_collector.mock['error_data'] = 'too human'
    response = @service.error_data([])
    assert_equal 'too human', response    
  end

  def test_transaction_sample_data
    $fake_collector.mock['transaction_sample_data'] = 'MPC1000'
    response = @service.transaction_sample_data([])
    assert_equal 'MPC1000', response        
  end

  def test_sql_trace_data
    $fake_collector.mock['sql_trace_data'] = 'explain this'
    response = @service.sql_trace_data([])
    assert_equal 'explain this', response
  end

  def test_request_timeout
    NewRelic::Control.instance['timeout'] = 600
    service = NewRelic::Agent::NewRelicService.new('abcdef', @server)
    assert_equal 600, service.request_timeout
  end
  
  def test_should_throw_received_errors
    assert_raise NewRelic::Agent::ServerConnectionException do
      @service.send(:invoke_remote, :bogus_method)
    end
  end  
end
