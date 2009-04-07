class NewRelic::Control::Rails < NewRelic::Control

  def env
    @env ||= RAILS_ENV
  end
  def root
    RAILS_ROOT
  end
  
  def log_path
    path = ::RAILS_DEFAULT_LOGGER.instance_eval do
      File.dirname(@log.path) rescue File.dirname(@logdev.filename) 
    end rescue "#{root}/log"
    File.expand_path(path)
  end
  # In versions of Rails prior to 2.0, the rails config was only available to 
  # the init.rb, so it had to be passed on from there.  
  def init_config(options={})
    rails_config=options[:config]
    if !agent_enabled?
      RAILS_DEFAULT_LOGGER.info "New Relic Agent not running"
    else
      RAILS_DEFAULT_LOGGER.info "Starting the New Relic Agent"
      install_developer_mode rails_config if developer_mode?
    end
  end
  
  def install_developer_mode(rails_config)
#    ActiveSupport::Dependencies.log_activity = true
    return if @installed
    @installed = true
    controller_path = File.expand_path(File.join(newrelic_root, 'ui', 'controllers'))
    helper_path = File.expand_path(File.join(newrelic_root, 'ui', 'helpers'))
#    $LOAD_PATH << controller_path
#    $LOAD_PATH << helper_path

    if defined? ActiveSupport::Dependencies
      Dir["#{helper_path}/*.rb"].each { |f| require f }
      Dir["#{controller_path}/*.rb"].each { |f| require f }
 #      ActiveSupport::Dependencies.load_paths << controller_path
#      ActiveSupport::Dependencies.load_paths << helper_path
    elsif defined? Dependencies.load_paths
      Dependencies.load_paths << controller_path
      Dependencies.load_paths << helper_path
    else
      to_stdout "ERROR: Rails version #{Rails::VERSION::STRING} too old for developer mode to work."
      return
    end
    install_devmode_route
    
    # If we have the config object then add the controller path to the list.
    # Otherwise we have to assume the controller paths have already been
    # set and we can just append newrelic.
    
    if rails_config
      rails_config.controller_paths << controller_path
    else
      current_paths = ActionController::Routing.controller_paths
      if current_paths.nil? || current_paths.empty?
        to_stdout "WARNING: Unable to modify the routes in this version of Rails.  Developer mode not available."
      end
      current_paths << controller_path
    end
    
    #ActionController::Routing::Routes.reload! unless NewRelic::Control.instance['skip_developer_route']
    
    # inform user that the dev edition is available if we are running inside
    # a webserver process
    if @local_env.dispatcher_instance_id
      port = @local_env.dispatcher_instance_id.to_s =~ /^\d+/ ? ":#{local_env.dispatcher_instance_id}" : ":port" 
      to_stdout "NewRelic Agent Developer Mode enabled."
      to_stdout "To view performance information, go to http://localhost#{port}/newrelic"
    end
  end
  
  protected 
  
  def install_devmode_route
    # This is a monkey patch to inject the developer tool route into the
    # parent app without requiring users to modify their routes. Of course this 
    # has the effect of adding a route indiscriminately which is frowned upon by 
    # some: http://www.ruby-forum.com/topic/126316#563328
    ActionController::Routing::RouteSet.class_eval do
      next if self.instance_methods.include? 'draw_with_newrelic_map'
      def draw_with_newrelic_map
        draw_without_newrelic_map do | map |
          map.named_route 'newrelic_developer', '/newrelic/:action/:id', :controller => 'newrelic' unless NewRelic::Control.instance['skip_developer_route']
          yield map        
        end
      end
      alias_method_chain :draw, :newrelic_map
    end
  end
  
  def rails_vendor_root
    File.join(root,'vendor','rails')
  end
  def git_info
    env_lang, ENV['LC_ALL'] = ENV['LC_ALL'], 'C'
    if File.directory? rails_vendor_root
      Dir.chdir(rails_vendor_root) do
        silence_stderr { `git log -n 1` }
      end
    else 
      ""
    end
  ensure
    ENV['LC_ALL'] = env_lang
  end
  
  def freeze_edge_version
    if File.exist?(rails_vendor_root)
      begin
        Dir[File.join(rails_vendor_root, 'REVISION_*')].first.scan(/_(\d+)$/).first.first
      rescue
        Dir[File.join(rails_vendor_root, 'TAG_*')].first.scan(/_(.+)$/).first.first rescue 'unknown'
      end
    end
  end

  # Collect the Rails::Info into an associative array as well as the list of plugins
  def append_environment_info
    local_env.append_environment_value('Rails version'){ ::Rails::VERSION::STRING }

    # The Rails Git revision, if it's checked out into vendor/rails.
    local_env.append_environment_value 'Edge Rails revision' do
      git_info[/commit ([a-z0-9-]+)/, 1] || freeze_edge_version
    end if File.directory?(rails_vendor_root)

    if ::Rails::VERSION::MAJOR * 100 + ::Rails::VERSION::MINOR * 10 >= 210
      local_env.append_gem_list do
        ::Rails.configuration.gems.map do | gem |
          version = (gem.respond_to?(:version) && gem.version) ||
                    (gem.specification.respond_to?(:version) && gem.specification.version)
          gem.name + (version ? "(#{version})" : "")
        end
      end
      # The plugins is configured manually.  If it's nil, it loads everything non-deterministically
      if ::Rails.configuration.plugins
         local_env.append_plugin_list { ::Rails.configuration.plugins }
      else
        ::Rails.configuration.plugin_paths.each do |path|
          local_env.append_plugin_list { Dir[File.join(path, '*')].collect{ |p| File.basename p if File.directory? p }.compact }
        end
      end
    else
      # Rails prior to 2.1, can't get the gems.  Find plugins in the default location
      local_env.append_plugin_list do
        Dir[File.join(root, 'vendor', 'plugins', '*')].collect{ |p| File.basename p if File.directory? p }.compact
      end
    end
  end
  
  def install_shim
    super
    require 'new_relic/agent/instrumentation/controller_instrumentation'
    ActionController::Base.send :include, NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim  
  end
end