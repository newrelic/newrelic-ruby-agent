class NewRelic::Config::Merb < NewRelic::Config
  
  def app; :merb; end
  
  def env
    @env ||= ::Merb.env
  end
  def root 
    ::Merb.root
  end
  
  def to_stderr(msg)
    STDERR.puts "NewRelic ~ " + msg 
  end
  
  def start_plugin
    ::Merb::Plugins.add_rakefiles File.join(newrelic_root,"lib/tasks/all.rb")
    
    # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
    ::Merb::Plugins.config[:newrelic] = {
      :config => self
    }
    
    ::Merb::BootLoader.before_app_loads do
      # require code that must be loaded before the application
    end
    
    if tracers_enabled?
      ::Merb::BootLoader.after_app_loads do
        start_agent
      end
    end
    
  end
end