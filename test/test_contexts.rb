# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module TestContexts
  def with_running_agent

    context 'with running agent' do # this is needed for the nested setups

      setup do
        @log_data = StringIO.new
        @log = Logger.new(@log_data)
        NewRelic::Agent::Agent.instance.service = default_service
        NewRelic::Agent.manual_start :log => @log
        @agent = NewRelic::Agent.instance
        @agent.transaction_sampler.send :clear_builder
        @agent.transaction_sampler.reset!
        @agent.stats_engine.clear_stats
      end

      yield

      def teardown
        super
        NewRelic::Agent.shutdown
        @log_data.reset
        NewRelic::Control.instance['dispatcher']=nil
        NewRelic::Control.instance['dispatcher_instance_id']=nil
      end

    end
  end
end
