# Control subclass instantiated when Rails is detected.  Contains
# Rails specific configuration, instrumentation, environment values,
# etc.
require 'new_relic/control/frameworks/rails'
class NewRelic::Control::Frameworks::Rails3 < NewRelic::Control::Frameworks::Rails

  def env
    @env ||= ::Rails.env.to_s
  end

  def root
    @root ||= Rails.root.to_s
  end

  def logger
    ::Rails.logger
  end


  def log!(msg, level=:info)
    return unless should_log?
    logger.send(level, msg)
  rescue Exception => e
    super
  end

  def to_stdout(msg)
    logger.info(msg)
  rescue
    super
  end

  def vendor_root
    @vendor_root ||= File.join(root,'vendor','rails')
  end

  def version
    @rails_version ||= NewRelic::VersionNumber.new(::Rails::VERSION::STRING)
  end

  protected

  # Collect the Rails::Info into an associative array as well as the list of plugins
  def append_environment_info
    local_env.append_environment_value('Rails version'){ version }
    local_env.append_environment_value('Rails threadsafe') do
      true == ::Rails.configuration.action_controller.allow_concurrency
    end
    local_env.append_environment_value('Rails Env') { env }
    local_env.append_gem_list do
      bundler_gem_list
    end
    local_env.append_plugin_list { ::Rails.configuration.plugins.to_a }
  end

end
