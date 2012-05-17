require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class PipeServiceTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent::PipeChannelManager.listener.stop    
    NewRelic::Agent::PipeChannelManager.register_report_channel(456)
    @service = NewRelic::Agent::PipeService.new(456)
  end

  def teardown
    @service.send(:reset_buffer)
  end
  
  def test_constructor
    assert_equal 456, @service.channel_id
  end
  
  def test_connect_returns_nil
    assert_nil @service.connect({}) 
  end
    
  def test_metric_data_buffers
    metric_data = generate_metric_data('Custom/test/method')
    @service.metric_data(0, 1, metric_data)
    
    expected_data = { metric_data[0].metric_spec => metric_data[0].stats }
    assert_equal expected_data, @service.stats_engine.stats_hash
  end
  
  def test_transaction_sample_data
    @service.transaction_sample_data(['txn'])
    assert_equal ['txn'], @service.buffer[:transaction_traces]
  end

  def test_error_data
    @service.error_data(['err'])
    assert_equal ['err'], @service.buffer[:error_traces]
  end

  def test_sql_trace_data
    @service.sql_trace_data(['sql'])
    assert_equal ['sql'], @service.buffer[:sql_traces]
  end

  if NewRelic::LanguageSupport.can_fork? && !NewRelic::LanguageSupport.using_version?('1.9.1')
    def test_shutdown_writes_data_to_pipe
      pid = Process.fork do
        metric_data0 = generate_metric_data('Custom/something')
        @service.metric_data(0.0, 0.1, metric_data0)
        @service.transaction_sample_data(['txn0'])
        @service.error_data(['err0'])
        @service.sql_trace_data(['sql0'])      
        @service.shutdown(Time.now)
      end
      Process.wait(pid)
      
      pipe = NewRelic::Agent::PipeChannelManager.channels[456]
      pipe.in.close
      received_data = Marshal.load(pipe.out.read)
      
      assert_equal 'Custom/something', received_data[:stats].keys.sort[0].name
      assert_equal ['txn0'], received_data[:transaction_traces]
      assert_equal ['err0'], received_data[:error_traces].sort
    end
  end
  
  def generate_metric_data(metric_name, data=1.0)
    engine = NewRelic::Agent::StatsEngine.new
    engine.get_stats_no_scope(metric_name).record_data_point(data)
    engine.harvest_timeslice_data({}, {}).values
  end
end
