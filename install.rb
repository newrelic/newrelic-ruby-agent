require 'ftools'

puts IO.read(File.join(File.dirname(__FILE__), 'README'))

dest_config_file = File.expand_path("#{File.dirname(__FILE__)}/../../../config/newrelic.yml")
src_config_file = "#{File.dirname(__FILE__)}/sample_config.yml"

unless File::exists? dest_config_file 
  File::copy src_config_file, dest_config_file, true
  puts "\nInstalling a default configuration file."
  puts "To monitor your application in production mode, you must enter a license key."
  puts "See #{dest_config_file}"
  puts "For a license key, sign up at http://rpm.newrelic.com/signup."
end  
