# run unit tests for the NewRelic Agent
namespace :newrelic do
  desc "Install a default config/newrelic.yml file"
  task :install do
    load File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "install.rb"))
  end

  namespace :config do
    desc "Describe available New Relic configuration settings."
    task :docs do
      require File.expand_path(File.join(File.dirname(__FILE__), "..", "new_relic", "agent", "configuration", "default_source.rb"))

      NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
        if value[:public]
          puts "Setting:      #{key}"
          if value[:type] == NewRelic::Agent::Configuration::Boolean
            puts "Type:         Boolean"
          else
            puts "Type:         #{value[:type]}"
          end
          puts 'Description:  ' + value[:description]
          puts "-" * (value[:description].length + 14)
        end
      end
    end
  end
end
