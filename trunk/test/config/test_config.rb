require 'new_relic/config/rails'
class NewRelic::Config::Test < NewRelic::Config::Rails
  def env
    'test'
  end
  def config_file
    File.join(File.dirname(__FILE__), "newrelic.yml")
  end
end