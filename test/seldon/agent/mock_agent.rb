require 'seldon/agent/stats_engine'

SELDON_AGENT_ENABLED = true
module Seldon
  module Agent
    
    class Agent
      attr_reader :stats_engine
      
      private_class_method :new
      @@instance = nil
      
      def Agent.in_rails_environment?
        true
      end
      
      def Agent.instance
        @@instance = new unless @@instance
        @@instance
      end
      
      def initialize
        @stats_engine = StatsEngine.new 
      end
    end
    
    class << self
      def agent
        Seldon::Agent::Agent.instance
      end
    end
  end
end
