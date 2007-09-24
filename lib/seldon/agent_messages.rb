require 'seldon/transaction_sample_rule'

module Seldon
  module AgentMessages
    class AddTransactionSampleRule
      def initialize(rule)
        @rule = rule
      end
      
      def execute(agent)
        "ADDING TRANSACTION SAMPLE RULE: #{@rule}"
        agent.transaction_sampler.add_rule(@rule)
      end
    end
  end
end