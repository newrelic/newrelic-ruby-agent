# This agent is loaded by the plug when the plug-in is disabled
# It recreates just enough of the API to not break any clients that
# invoke the Agent.
class NewRelic::Agent::ShimAgent < NewRelic::Agent::Agent
  def self.instance
    @instance ||= self.new
  end  
  def ensure_worker_thread_started; end
  def start *args; end
  def shutdown; end
end
