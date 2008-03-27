require 'newrelic/agent/transaction_sampler'
require 'test/unit'

::RPM_DEVELOPER = false unless defined? ::RPM_DEVELOPER

module NewRelic 
  module Agent
    class TransationSamplerTests < Test::Unit::TestCase
      
      def test_multiple_samples
        @sampler = TransactionSampler.new
      
        run_sample_trace
        run_sample_trace
        run_sample_trace
        run_sample_trace
      
        samples = @sampler.get_samples
        assert samples.length == 4
        assert samples.first.root_segment.called_segments[0].metric_name == "a"
        assert samples.last.root_segment.called_segments[0].metric_name == "a"
      end
      
      
      def test_harvest_slowest
        @sampler = TransactionSampler.new
        
        run_sample_trace
        run_sample_trace
        run_sample_trace { sleep 0.5 }
        run_sample_trace
        run_sample_trace
        
        slowest = @sampler.harvest_slowest_sample(nil)
        assert slowest.duration >= 0.5
        
        run_sample_trace { sleep 0.2 }
        not_as_slow = @sampler.harvest_slowest_sample(slowest)
        assert not_as_slow == slowest
        
        run_sample_trace { sleep 0.6 }
        new_slowest = @sampler.harvest_slowest_sample(slowest)
        assert new_slowest != slowest
        assert new_slowest.duration >= 0.6
      end
      
      def test_preare_to_send
        @sampler = TransactionSampler.new

        run_sample_trace { sleep 0.2 }
        sample = @sampler.harvest_slowest_sample(nil)
        
        ready_to_send = sample.prepare_to_send
        assert sample.duration == ready_to_send.duration
        
        # TODO test for SQL cleansing, backtrace, etc.
      end
      
    private      
      def run_sample_trace(&proc)
        @sampler.notice_first_scope_push
        @sampler.notice_transaction '/path', nil, {}
        @sampler.notice_push_scope "a"
        @sampler.notice_push_scope "ab"
        proc.call if proc
        @sampler.notice_pop_scope "ab"
        @sampler.notice_push_scope "lew"
        @sampler.notice_pop_scope "lew"
        @sampler.notice_pop_scope "a"
        @sampler.notice_scope_empty
      end
      
    end
  end
end

