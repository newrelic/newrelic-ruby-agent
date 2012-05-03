require 'ostruct'

class FakeService
  attr_accessor :request_timeout, :agent_id, :agent_data, :collector

  def initialize
    @agent_data = []
    @supported_methods = [ :connect, :metric_data, :transaction_sample_data,
                           :error_data, :sql_trace_data, :shutdown ]
    @collector = NewRelic::Control::Server.new(:name => 'fakehost', :port => 0)
  end

  def method_missing(method, *args)
    if @supported_methods.include?(method)
      @agent_data << OpenStruct.new(:method => method, :params => args)
      {}
    else
      super
    end
  end  
end
