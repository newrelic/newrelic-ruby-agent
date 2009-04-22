module NewRelic; TEST = true; end unless defined? NewRelic::TEST

NEWRELIC_PLUGIN_DIR = File.expand_path(File.join(File.dirname(__FILE__),".."))
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"test")
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"ui/helpers")
$LOAD_PATH.uniq!

require File.expand_path(File.join(NEWRELIC_PLUGIN_DIR, "..","..","..","config","environment"))

require 'test_help'
require 'mocha'
require 'test/unit'

=begin
# This is a mixin for hacking the select method
if defined? ActiveRecord::ConnectionAdapters
  class ActiveRecord::ConnectionAdapters::MysqlAdapter
    
    def log_info_with_slowdown(sql, name, seconds)
      log_info_without_slowdown(sql, name, seconds)
      sleep 0.1
    end
    
    def setup_slow
      self.class.alias_method_chain :log_info, :slowdown
    end
    
    def teardown_slow
      alias :log_info :log_info_without_slowdown
    end
  end
end
=end