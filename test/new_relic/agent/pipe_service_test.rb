require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class PipeServiceTest < Test::Unit::TestCase

	def setup
		NewRelic::Agent::PipeChannelManager.register_report_channel(456)
		@service = NewRelic::Agent::PipeService.new(456)
	end

	def test_constructor
		assert_equal 456, @service.channel_id
	end

	def test_connect_returns_nil
		assert_nil @service.connect({}) 
	end

	def test_shutdown_closes_report_channel
		@service.shutdown(Time.now)
		assert NewRelic::Agent::PipeChannelManager.channels[456].in.closed?
	end

	def test_metric_data_posts_pipe
		metric = 'Custom/test/method'
		engine = NewRelic::Agent.agent.stats_engine
    engine.get_stats_no_scope(metric).record_data_point(1.0)
    sent_data = engine.harvest_timeslice_data({},{}).values
    @service.metric_data(0.0, 0.1, sent_data)

    received_data = Marshal.load(NewRelic::Agent::PipeChannelManager.channels[456].out.read)
    assert_equal sent_data, received_data
  end
end