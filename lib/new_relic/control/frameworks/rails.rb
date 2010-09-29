# Control subclass instantiated when Rails is detected.  Contains
# Rails specific configuration, instrumentation, environment values,
# etc.
class NewRelic::Control::Frameworks::Rails < NewRelic::Control

  def env
    @env ||= RAILS_ENV.dup
  end
  def root
    RAILS_ROOT
  end

  # In versions of Rails prior to 2.0, the rails config was only available to
  # the init.rb, so it had to be passed on from there.
  def init_config(options={})
    rails_config=options[:config]
    if !agent_enabled?
      # Might not be running if it does not think mongrel, thin, passenger, etc
      # is running, if it things it's a rake task, or if the agent_enabled is false.
      log! "New Relic Agent not running."
    else
      log! "Starting the New Relic Agent."
      install_developer_mode rails_config if developer_mode?
      install_episodes rails_config
    end
  end

  def install_episodes(config)
    return if config.nil? || !config.respond_to?(:middleware) || !episodes_enabled?
    config.after_initialize do
      if defined?(NewRelic::Rack::Episodes)
        config.middleware.use NewRelic::Rack::Episodes
        log! "Installed episodes middleware"
        ::RAILS_DEFAULT_LOGGER.info "Installed episodes middleware"
      end
    end
  end

  def install_developer_mode(rails_config)
    return if @installed
    @installed = true
    if rails_config && rails_config.respond_to?(:middleware)
      begin
        require 'new_relic/rack/developer_mode'
        rails_config.middleware.use NewRelic::Rack::DeveloperMode

        # inform user that the dev edition is available if we are running inside
        # a webserver process
        if @local_env.dispatcher_instance_id
          port = @local_env.dispatcher_instance_id.to_s =~ /^\d+/ ? ":#{local_env.dispatcher_instance_id}" : ":port"
          log!("NewRelic Agent Developer Mode enabled.")
          log!("To view performance information, go to http://localhost#{port}/newrelic")
        end
      rescue Exception => e
        log!("Error installing New Relic Developer Mode: #{e.inspect}", :error)
      end
    else
      log!("Developer mode not available for Rails versions prior to 2.2", :warn)
    end
  end

  def log!(msg, level=:info)
    return unless should_log?
    begin
      ::RAILS_DEFAULT_LOGGER.send(level, msg)
    rescue Exception => e
      super
    end
  end

  def to_stdout(message)
    ::RAILS_DEFAULT_LOGGER.info(message)
  rescue Exception => e
    super
  end

  def rails_version
    @rails_version ||= NewRelic::VersionNumber.new(::Rails::VERSION::STRING)
  end

  protected

  def rails_vendor_root
    File.join(root,'vendor','rails')
  end

  def rails_gem_list
    ::Rails.configuration.gems.map do | gem |
      version = (gem.respond_to?(:version) && gem.version) ||
        (gem.specification.respond_to?(:version) && gem.specification.version)
      gem.name + (version ? "(#{version})" : "")
    end
  end
  
  # Collect the Rails::Info into an associative array as well as the list of plugins
  def append_environment_info
    local_env.append_environment_value('Rails version'){ ::Rails::VERSION::STRING }
    if rails_version >= NewRelic::VersionNumber.new('2.2.0')
      local_env.append_environment_value('Rails threadsafe') do
        ::Rails.configuration.action_controller.allow_concurrency == true
      end
    end
    local_env.append_environment_value('Rails Env') { ENV['RAILS_ENV'] }
    if rails_version >= NewRelic::VersionNumber.new('2.1.0')
      local_env.append_gem_list do
        (bundler_gem_list + rails_gem_list).uniq
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
