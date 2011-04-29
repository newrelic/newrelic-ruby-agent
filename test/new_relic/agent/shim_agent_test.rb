require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
module NewRelic
  module Agent
    class ShimAgentTest < Test::Unit::TestCase
      
      def setup
        super
        @agent = NewRelic::Agent::ShimAgent.new
      end

      def test_serialize
        assert_equal(nil, @agent.serialize, "should return nil when shut down")
      end

      def test_merge_data_from
        assert_equal(nil, @agent.merge_data_from(mock('metric data')))
      end
      
      def test_harvest_transaction_traces
        assert_equal(nil, @agent.send(:harvest_transaction_traces), 'should return nil when shut down')
      end
      
      def test_harvest_timeslice_data
        assert_equal(nil, @agent.send(:harvest_timeslice_data), 'should return nil when shut down')
      end
      
      def test_harvest_errors
        assert_equal(nil, @agent.send(:harvest_errors), 'should return nil when shut down')
      end

    end
  end
end
