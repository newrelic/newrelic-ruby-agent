class NewRelic::Config::Merb < NewRelic::Config
  
  def app; :merb; end
  
  def env
    Merb.env
  end
  def root 
    Merb.root
  end
  
  def to_stderr(msg)
    STDERR.puts "NewRelic ~ " + msg 
  end
  
  def start_plugin
    if !tracers_enabled?
      #require 'new_relic/shim_agent'
      return
    end
    
    # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
    Merb::Plugins.config[:newrelic] = {
      :config => self
    }
    
    Merb::BootLoader.before_app_loads do
      # require code that must be loaded before the application
    end
    
    Merb::BootLoader.after_app_loads do
      start_agent
    end
    
    # TODO: add task to install newrelic.yml in dev mode
    # Merb::Plugins.add_rakefiles "newrelic/merbtasks"
  end
end