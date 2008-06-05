require 'newrelic/agent/transaction_sampler'
require 'test/unit'

::RPM_DEVELOPER = true unless defined? ::RPM_DEVELOPER

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
        assert_equal 4, samples.length
        assert_equal "a", samples.first.root_segment.called_segments[0].metric_name
        assert_equal "a", samples.last.root_segment.called_segments[0].metric_name
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
      end
      
      def test_multithread
        @sampler = TransactionSampler.new
        threads = []
        
        20.times do
          t = Thread.new(@sampler) do |the_sampler|
            @sampler = the_sampler
            100.times do
              run_sample_trace { sleep 0.01 }
            end
          end
          
          threads << t
        end
        threads.each {|t| t.join }
      end
      
      def test_sample_with_parallel_paths
        @sampler = TransactionSampler.new
        
        @sampler.notice_first_scope_push
        @sampler.notice_transaction "/path", nil, {}
        @sampler.notice_push_scope "a"
        @sampler.notice_pop_scope "a"
        @sampler.notice_scope_empty
        
        @sampler.notice_first_scope_push
        @sampler.notice_transaction "/path", nil, {}
        @sampler.notice_push_scope "a"
        @sampler.notice_pop_scope "a"
        @sampler.notice_scope_empty
      end
      
      def test_double_scope_stack_empty
        @sampler = TransactionSampler.new
        
        @sampler.notice_first_scope_push
        @sampler.notice_transaction "/path", nil, {}
        @sampler.notice_push_scope "a"
        @sampler.notice_pop_scope "a"
        @sampler.notice_scope_empty
        @sampler.notice_scope_empty
        @sampler.notice_scope_empty
        @sampler.notice_scope_empty
        
        assert_not_nil @sampler.harvest_slowest_sample(nil)
      end
      
    private      
      def run_sample_trace(&proc)
        @sampler.notice_first_scope_push
        @sampler.notice_transaction '/path', nil, {}
        @sampler.notice_push_scope "a"
        @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'")
        @sampler.notice_push_scope "ab"
        @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'")
        proc.call if proc
        @sampler.notice_pop_scope "ab"
        @sampler.notice_push_scope "lew"
        @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'")
        @sampler.notice_pop_scope "lew"
        @sampler.notice_pop_scope "a"
        @sampler.notice_scope_empty
      end
      
    end
  end
end

