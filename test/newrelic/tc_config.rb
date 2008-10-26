require 'newrelic/config/rails'
class NewRelic::Config::Test < NewRelic::Config::Rails
  def app; :test; end
  def env
    'test'
  end
  def config_file
    File.join(File.dirname(__FILE__), "newrelic.yml")
  end
#  def root
#    File.expand_path(File.join(File.dirname(__FILE__), "..", "..","..","test"))
#  end
  
end