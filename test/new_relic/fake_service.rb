require 'ostruct'

module NewRelic
  class FakeService
    attr_accessor :request_timeout, :agent_id, :agent_data, :collector, :mock
    
    def initialize
      @agent_data = []
      @supported_methods = [ :connect, :metric_data, :transaction_sample_data,
                             :error_data, :sql_trace_data, :shutdown ]
      @collector = NewRelic::Control::Server.new(:name => 'fakehost', :port => 0)
      @id_counter = 0
      @base_expectations = {
        'get_redirect_host'       => 'localhost',
        'connect'                 => { 'agent_run_id' => agent_run_id },
        'metric_data'             => { 'Some/Metric/Spec' => 1 },
        'sql_trace_data'          => nil,
        'transaction_sample_data' => nil,
        'error_data'              => nil,
        'shutdown'                => nil,
      }
      reset
    end

    def agent_run_id
      @id_counter += 1
    end

    def reset
      @mock = @base_expectations.dup
      @id_counter = 0
      @agent_data = []
    end
    
    def method_missing(method, *args)
      if @supported_methods.include?(method)
        @agent_data << OpenStruct.new(:action => method, :params => args)
        @mock[method.to_s]
      else
        super
      end
    end  
  end
end
