module NewRelic; TEST = true; end unless defined? NewRelic::TEST

NEWRELIC_PLUGIN_DIR = File.expand_path(File.join(File.dirname(__FILE__),".."))
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"test")
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"ui/helpers")
$LOAD_PATH.uniq!

require File.expand_path(File.join(NEWRELIC_PLUGIN_DIR, "..","..","..","config","environment"))

require 'test_help'
require 'mocha'
require 'test/unit'

def assert_between(floor, ceiling, value, message = nil)
  assert floor <= value && value <= ceiling,
  message || "expected #{floor} <= #{value} <= #{ceiling}"
end
