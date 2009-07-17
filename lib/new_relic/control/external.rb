# This is the control used when starting up in the context of 
# The New Relic Infrastructure Agent.  We want to call this
# out specifically because in this context we are not monitoring
# the running process, but actually external things.
class NewRelic::Control::Monitor < NewRelic::Control::Ruby

  def init_config(options={})
    super
  end
  
end