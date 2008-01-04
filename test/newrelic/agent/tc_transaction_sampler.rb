require 'newrelic/agent/transaction_sampler'
require 'newrelic/transaction_sample_rule'
require 'test/unit'

module NewRelic 
  module Agent
    class TransationSamplerTests < Test::Unit::TestCase
      
      def test_sample_with_one_rule
        @sampler = TransactionSampler.new
        rule = new_rule("lew")
        @sampler.add_rule(rule)

        run_sample_trace

        samples = @sampler.harvest_samples
        assert samples.length == 1
        assert samples.first.root_segment.called_segments[0].metric_name == "a"
      end
      
      def test_sample_with_no_rules
        @sampler = TransactionSampler.new
        run_sample_trace
      
        samples = @sampler.harvest_samples
        assert samples.length == 0
      end
      
      def test_sample_with_one_false_rule
        @sampler = TransactionSampler.new
        rule = new_rule("no match")
        @sampler.add_rule(rule)
      
        run_sample_trace
      
        samples = @sampler.harvest_samples
        assert samples.length == 0
      end
      
      def test_multiple_samples
        @sampler = TransactionSampler.new
        rule = new_rule("lew")
        @sampler.add_rule(rule)
      
        run_sample_trace
        run_sample_trace
        run_sample_trace
        run_sample_trace
      
        samples = @sampler.harvest_samples
        assert samples.length == 4
        assert samples.first.root_segment.called_segments[0].metric_name == "a"
        assert samples.last.root_segment.called_segments[0].metric_name == "a"
      end
      
      def test_midstream_rule_addition
        @sampler = TransactionSampler.new
        run_sample_trace do 
          # insert a rule that would match mid-transaction - this should not result in
          # a traced sample.
          rule = new_rule("lew")
          @sampler.add_rule(rule)
        end
      
        samples = @sampler.harvest_samples
        assert samples.length == 0
        
        # the next transaction should get sampled
        run_sample_trace
        samples = @sampler.harvest_samples(samples)
        assert samples.length == 1
      end
      
      def test_rule_removal
        @sampler = TransactionSampler.new
        rule = NewRelic::TransactionSampleRule.new("lew", 1, 10000)
        @sampler.add_rule(rule)
        
        run_sample_trace
        run_sample_trace
        run_sample_trace
        samples = @sampler.harvest_samples
        assert samples.length == 1
      end
        
      def new_rule(metric)
        @sampler = TransactionSampler.new
        NewRelic::TransactionSampleRule.new(metric,100,100)
      end
      
      def run_sample_trace(&proc)
        @sampler.notice_first_scope_push
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

