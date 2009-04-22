class NewRelic::Control::Merb < NewRelic::Control
  
  def env
    @env ||= ::Merb.env
  end
  def root 
    ::Merb.root
  end
  
  def to_stdout(msg)
    STDOUT.puts "NewRelic ~ " + msg 
  end
  
  def init_config options={}
    ::Merb::Plugins.add_rakefiles File.join(newrelic_root,"lib/tasks/all.rb")
    
    # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
    ::Merb::Plugins.config[:newrelic] = {
      :config => self
    }
  end
  def start_agent
    ::Merb::BootLoader.after_app_loads do
       super
    end unless @started_already
  end
end