ENV["RAILS_ENV"] = "test"
require 'rubygems'
require 'mocha'
require 'test/unit'

unless defined? NEWRELIC_PLUGIN_DIR
  NEWRELIC_PLUGIN_DIR = File.expand_path(File.dirname(__FILE__)+"/..")
  $LOAD_PATH << NEWRELIC_PLUGIN_DIR
  $LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"lib")
  $LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"test")
  $LOAD_PATH.uniq!
end

require 'newrelic/config'

module NewRelic
  module Agent
    class Agent
      def start_with_block_logging(environment, identifier, force=false)
        silence_stream(::STDERR) { self.start_without_block_logging(environment, identifier, force) }
      end
      alias_method_chain :start, :block_logging rescue nil
    end
  end
end

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
