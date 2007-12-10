require 'seldon/agent/stats_engine'
require File.join(File.dirname(__FILE__),'mock_agent')

SELDON_AGENT_ENABLED = true
module Seldon
  module Agent
    
    class Agent
      attr_reader :stats_engine
      
      private_class_method :new
      @@instance = nil
      
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
