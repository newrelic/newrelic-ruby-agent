$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '..','..'))
require 'new_relic/rack'
use Rack::CommonLogger
use Rack::ShowExceptions
run NewRelic::Rack::MetricApp.new

