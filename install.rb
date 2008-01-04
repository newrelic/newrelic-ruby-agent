require 'ftools'

puts IO.read(File.join(File.dirname(__FILE__), 'README'))

dest_config_file = "#{File.dirname(__FILE__)}/../../../config/newrelic.yml"
src_config_file = "#{File.dirname(__FILE__)}/sample_config.yml"

unless File::exists? dest_config_file
  puts "\nInstalling a default configuration file.  Be sure to edit these settings to enable the NewRelic Agent.\n"
  File::copy src_config_file, dest_config_file, true
end  
