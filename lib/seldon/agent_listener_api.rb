require 'action_web_service'
require 'seldon/metric_data'
require 'seldon/transaction_sample'
require 'seldon/stats'
require 'xmlrpc/utils'

module Seldon
	class AgentListenerAPI < ActionWebService::API::Base
    # def launch(host, port, pid, launch_time) returns agent_run_id
	  api_method :launch, :expects => [:string, :int, :int, Time], :returns => [:int]

    # def metric_data(agent_run_id, begin_timeslice, end_timeslice, [Seldon::MetricData])
    # returns [(Serialized) [Seldon::AgentMessage]]
    api_method :metric_data, :expects=>[:int, :float, :float, [Seldon::MetricData]], :returns => [[:string]]

    # def transaction_sample_data(agent_run_id, [Serialized: TransactionSample])
    # returns [(Serialized) [Seldon::AgentMessage]]
    api_method :transaction_sample_data, :expects => [:int, [Seldon::TransactionSample]], :returns => [[:string]]
    
    # def session_capture_data([Hash(:uri => String, :timestamp => float])
    # returns [(Serialized) [Seldon::AgentMessage]]
    api_method :session_capture_data, :expects => [[:string]], :returns => [[:string]]
    
    # def ping(agent_run_id) 
    # returns [(Serialized) [Seldon::AgentMessage]]
    api_method :ping, :expects => [:int], :returns => [[:string]]
  end
  
  # make the classes that used as arguments serializable for XML-RPC
  class MetricData
    include XMLRPC::Marshallable
  end

  class MetricSpec
    include XMLRPC::Marshallable
  end
  
  class MethodTraceStats
    include XMLRPC::Marshallable
  end
  
  class TransactionSample
    include XMLRPC::Marshallable
    class Segment 
      include XMLRPC::Marshallable
    end
  end
      
end
