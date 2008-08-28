

require 'test/unit'
require 'newrelic/agent/testable_agent'



module Thin
  class Server
    def initialize
      @backend = Backend.new
    end
    
    def backend
      @backend
    end
  end
  
  class Backend
    
    def set_socket(s)
      @socket = s
    end
    def socket
      @socket
    end
  end
end



class AgentTests < Test::Unit::TestCase
  
  def test_public_apis
    agent = NewRelic::Agent.agent
    
    assert agent.is_a?(NewRelic::Agent::Agent)
        
    agent = NewRelic::Agent.instance
    
    assert agent.is_a?(NewRelic::Agent::Agent)

    begin
      NewRelic::Agent.set_sql_obfuscator(:unknown) do |sql|
        puts sql
      end
      fail
    rescue
      # ok
    end
    
    
    ignore_called = false
    NewRelic::Agent.ignore_error_filter do |e|
      ignore_called = true
      nil
    end
    
    NewRelic::Agent.agent.error_collector.notice_error('path', nil, {:x => 'y'}, ActionController::RoutingError.new("message"))
    
    assert ignore_called    
  end
  
  def test_thin
    
    thin = Thin::Server.new
    
    agent = NewRelic::Agent.instance
    
    thin.backend.set_socket("/application1/thin.0.sock")
    
    port1 = agent.determine_environment_and_port
    
    thin.backend.set_socket("/application2/thin.0.sock")
    port2 = agent.determine_environment_and_port
    
    assert_equal agent.environment, :thin
    assert_not_equal port1, port2
    
  end
  
end