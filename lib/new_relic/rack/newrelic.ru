# This is so that we don't detect a dispatcher like mongrel and think we are
# monitoring it.
ENV['NEWRELIC_DISPATCHER'] = 'none'

$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '..','..'))

require 'new_relic/rack'
puts ENV.inspect
appname ||= 'EPM Agent'
license_key ||= nil
use Rack::CommonLogger if defined?(logging) && logging
use Rack::ShowExceptions
map "http://localhost/metrics" do
  run NewRelic::Rack::MetricApp.new(appname, license_key)
end
map "/" do
  run NewRelic::Rack::Status.new
end


