require "test/unit"
require "newrelic/transaction_sample_rule"

module NewRelic
  class TransactionSamplerRuleTests < Test::Unit::TestCase
    def test_sample_all_with_metric
      rule = TransactionSampleRule.new("lew", 10000000, 10000000)
      
      assert !rule.has_expired?
      
      assert rule.check("lew")
      assert !rule.check("kirsten")
      assert !rule.has_expired?
      assert !rule.has_expired?
      assert !rule.has_expired?
      assert !rule.has_expired?
    end
    
    def test_sample_n_with_metric
      n = 3
      rule = TransactionSampleRule.new("lew", 3, 10000000)
      
      n.times do
        assert !rule.check("kirsten")
        assert !rule.has_expired?
        assert rule.check("lew")
      end
      
      assert rule.has_expired?
      assert !rule.check("lew")
    end
    
    def test_sample_one_with_metric
      rule = TransactionSampleRule.new("lew", 1, 10000000)
      assert !rule.has_expired?
      assert rule.check("lew")
      assert rule.has_expired?
      assert !rule.check("lew")
    end

    def test_sample_for_n_seconds
      rule = TransactionSampleRule.new("lew", 1000000, 0.2)
      assert rule.check("lew")
      assert !rule.has_expired?
      assert rule.check("lew")
      assert rule.check("lew")
      assert !rule.has_expired?
      assert !rule.check("katelyn")
      
      sleep 0.2
      assert rule.has_expired?
      assert !rule.check("lew")
    end
  end
end
