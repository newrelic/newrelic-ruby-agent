require 'new_relic/config/rails'
class NewRelic::Config::Test < NewRelic::Config::Rails
  def env
    'test'
  end
  def config_file
    File.join(File.dirname(__FILE__), "newrelic.yml")
  end
  def initialize
    super
    setup_log env
  end
  # when running tests, don't write out stderr
  def log!(msg, level=:info)
    log.send level, msg if log
  end
  
  # Not installing routes in test mode.  We don't
  # have functional tests yet.
  def install_devmode_route
    # no-op
  end
end