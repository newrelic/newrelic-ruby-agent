# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class PipeServiceTest < Minitest::Test
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

  # a #session method is required of services, though in the case of the
  # PipeService all it does is invoke the block it's passed.
  def test_session_invokes_block
    block_ran = false
    @service.session do
      block_ran = true
    end
    assert(block_ran)
  end

  def test_write_to_missing_pipe_logs_error
    ::NewRelic::Agent.logger.expects(:error) \
      .with(regexp_matches(/No communication channel to parent process/)).once
    service = NewRelic::Agent::PipeService.new(:non_existant)
    service.metric_data({})
  end

  if NewRelic::LanguageSupport.can_fork? &&
      !NewRelic::LanguageSupport.using_version?('1.9.1')

    def test_metric_data
      received_data = data_from_forked_process do
        metric_data0 = generate_metric_data('Custom/something')
        @service.metric_data(metric_data0)
      end

      assert_equal 'Custom/something', received_data[:metric_data].to_h.keys.sort[0].name
    end

    def test_transaction_sample_data
      received_data = data_from_forked_process do
        @service.transaction_sample_data(['txn'])
      end

      assert_equal ['txn'], received_data[:transaction_sample_data]
    end

    def test_error_data
      received_data = data_from_forked_process do
        @service.error_data(['err'])
      end
      assert_equal ['err'], received_data[:error_data]
    end

    def test_error_event_data
      received_data = data_from_forked_process do
        @service.error_event_data(['err_ev'])
      end
      assert_equal ['err_ev'], received_data[:error_event_data]
    end

    def test_sql_trace_data
      received_data = data_from_forked_process do
        @service.sql_trace_data(['sql'])
      end
      assert_equal ['sql'], received_data[:sql_trace_data]
    end

    def test_analytic_event_data
      received_data = data_from_forked_process do
        @service.analytic_event_data(['events'])
      end
      assert_equal ['events'], received_data[:analytic_event_data]
    end

    def test_custom_event_data
      received_data = data_from_forked_process do
        @service.custom_event_data(['events'])
      end
      assert_equal ['events'], received_data[:custom_event_data]
    end

    def test_transaction_sample_data_with_newlines
      payload_with_newline = "foo\n\nbar"
      received_data = data_from_forked_process do
        @service.transaction_sample_data([payload_with_newline])
      end
      assert_equal [payload_with_newline], received_data[:transaction_sample_data]
    end

    def test_multiple_writes_to_pipe
      pid = Process.fork do
        metric_data0 = generate_metric_data('Custom/something')
        @service.metric_data(metric_data0)
        @service.transaction_sample_data(['txn0'])
        @service.error_data(['err0'])
        @service.sql_trace_data(['sql0'])
        @service.shutdown(Time.now)
      end
      Process.wait(pid)

      received_data = read_from_pipe

      assert_equal 'Custom/something', received_data[:metric_data].to_h.keys.sort[0].name
      assert_equal ['txn0'], received_data[:transaction_sample_data]
      assert_equal ['err0'], received_data[:error_data].sort
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
    engine.harvest!
  end

  def read_from_pipe
    pipe = NewRelic::Agent::PipeChannelManager.channels[:pipe_service_test]
    data = {}
    while payload = pipe.read
      endpoint, data_for_endpoint = Marshal.load(payload)
      data.merge!(endpoint => data_for_endpoint)
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
