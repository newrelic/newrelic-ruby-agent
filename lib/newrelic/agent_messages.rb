require 'newrelic/transaction_sample_rule'

module NewRelic
  module AgentMessages
    class AddTransactionSampleRule
      def initialize(rule)
        @rule = rule
      end
      
      def execute(agent)
        agent.transaction_sampler.add_rule(@rule)
      end
    end
  end
end