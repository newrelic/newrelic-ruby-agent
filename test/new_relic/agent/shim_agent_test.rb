require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
module NewRelic
  module Agent
    class ShimAgentTest < Test::Unit::TestCase
      
      def setup
        super
        @agent = NewRelic::Agent::ShimAgent.new
      end

      def test_serialize
        @agent = NewRelic::Agent::ShimAgent.new
        assert_equal(nil, @agent.send(:serialize), "should return nil when shut down")
      end
      
      def test_harvest_transaction_traces
        @agent = NewRelic::Agent::ShimAgent.new        
        assert_equal(nil, @agent.send(:harvest_transaction_traces), 'should return nil when shut down')
      end
      
      def test_harvest_timeslice_data
        @agent = NewRelic::Agent::ShimAgent.new        
        assert_equal(nil, @agent.send(:harvest_timeslice_data), 'should return nil when shut down')
      end
      
      def test_harvest_errors
        @agent = NewRelic::Agent::ShimAgent.new        
        assert_equal(nil, @agent.send(:harvest_errors), 'should return nil when shut down')
      end
    end
  end
end
