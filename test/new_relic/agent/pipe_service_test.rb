require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class PipeServiceTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent::PipeChannelManager.listener.stop    
    NewRelic::Agent::PipeChannelManager.register_report_channel(:pipe_service_test)
    @service = NewRelic::Agent::PipeService.new(:pipe_service_test)
  end
  
  def test_constructor
    assert_equal :pipe_service_test, @service.channel_id
  end
  
  def test_connect_returns_nil
    assert_nil @service.connect({}) 
  end
  
  if NewRelic::LanguageSupport.can_fork? &&
      !NewRelic::LanguageSupport.using_version?('1.9.1')

    def test_metric_data
      received_data = data_from_forked_process do
        metric_data0 = generate_metric_data('Custom/something')
        @service.metric_data(0.0, 0.1, metric_data0)
      end

      assert_equal 'Custom/something', received_data[:stats].keys.sort[0].name
    end

    def test_transaction_sample_data
      received_data = data_from_forked_process do
        @service.transaction_sample_data(['txn'])
      end

      assert_equal ['txn'], received_data[:transaction_traces]
    end

    def test_error_data
      received_data = data_from_forked_process do
        @service.error_data(['err'])
      end
      assert_equal ['err'], received_data[:error_traces]
    end

    def test_sql_trace_data
      received_data = data_from_forked_process do
        @service.sql_trace_data(['sql'])
      end
      assert_equal ['sql'], received_data[:sql_traces]
    end

    def test_multiple_writes_to_pipe
      pid = Process.fork do
        metric_data0 = generate_metric_data('Custom/something')
        @service.metric_data(0.0, 0.1, metric_data0)
        @service.transaction_sample_data(['txn0'])
        @service.error_data(['err0'])
        @service.sql_trace_data(['sql0'])      
        @service.shutdown(Time.now)
      end
      Process.wait(pid)
      
      received_data = read_from_pipe
      
      assert_equal 'Custom/something', received_data[:stats].keys.sort[0].name
      assert_equal ['txn0'], received_data[:transaction_traces]
      assert_equal ['err0'], received_data[:error_traces].sort
    end

    def test_shutdown_sends_EOF
      received_data = data_from_forked_process do
        @service.shutdown(Time.now)
      end
      assert_equal 'EOF', received_data[:EOF]
    end
    
    def test_shutdown_closes_pipe
      data_from_forked_process do
        @service.shutdown(Time.now)
        assert NewRelic::Agent::PipeChannelManager \
          .channels[:pipe_service_test].closed?
      end
    end
  end
  
  def generate_metric_data(metric_name, data=1.0)
    engine = NewRelic::Agent::StatsEngine.new
    engine.get_stats_no_scope(metric_name).record_data_point(data)
    engine.harvest_timeslice_data({}, {}).values
  end

  def read_from_pipe
    pipe = NewRelic::Agent::PipeChannelManager.channels[:pipe_service_test]
    pipe.in.close
    data = {}
    while payload = pipe.out.gets("\n\n")
      got = Marshal.load(payload)
      if got == 'EOF'
        got = {:EOF => 'EOF'}
      end
      data.merge!(got)
    end
    data
  end

  def data_from_forked_process
    pid = Process.fork do
      yield
    end
    Process.wait(pid)
    read_from_pipe
  end
end
