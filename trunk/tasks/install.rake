# run unit tests for the NewRelic Agent
namespace :newrelic do
  AGENT_HOME = "vendor/plugins/newrelic_rpm"  
  
  desc "install a default config/newrelic.yml file"
  task :install => :environment do
    load File.join(AGENT_HOME, "install.rb")
  end
end