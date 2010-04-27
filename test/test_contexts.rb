
module TestContexts
  def with_running_agent
    
    context 'with running agent' do # this is needed for the nested setups
      
      setup do
        NewRelic::Agent.manual_start
      end
      
      yield
      
    end
  end
end