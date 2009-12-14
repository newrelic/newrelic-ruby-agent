class NewRelic::Agent::Sampler
  attr_accessor :stats_engine
  attr_reader :id
  def initialize(id)
    @id = id
  end
  
  def poll
    raise "Implement in the subclass"
  end
  
end