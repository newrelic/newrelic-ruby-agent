# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic; TEST = true; end unless defined? NewRelic::TEST
ENV['RAILS_ENV'] = 'test'
NEWRELIC_PLUGIN_DIR = File.expand_path(File.join(File.dirname(__FILE__),".."))
$LOAD_PATH << '.'
$LOAD_PATH << '../../..'
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"lib")
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"test")
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"ui/helpers")
$LOAD_PATH.uniq!

require 'rubygems'
require 'rake'

Dir.glob(File.join(NEWRELIC_PLUGIN_DIR,'test/helpers/*.rb')).each do |helper|
  require helper
end

# We can speed things up in tests that don't need to load rails.
# You can also run the tests in a mode without rails.  Many tests
# will be skipped.
if ENV["NO_RAILS"]
  puts "Running tests in standalone mode without Rails."
  require 'newrelic_rpm'
else
  begin
    require 'config/environment'
  #   require File.join(File.dirname(__FILE__),'..','..','rpm_test_app','config','environment')

    # we need 'rails/test_help' for Rails 4
    # we need 'test_help' for Rails 2
    # we need neither for Rails 3
    begin
      require 'rails/test_help'
    rescue LoadError
      begin
        require 'test_help'
      rescue LoadError
        # ignore load problems on test help - it doesn't exist in rails 3
      end
    end
    require 'newrelic_rpm'
  rescue LoadError => e
    puts "Running tests in standalone mode."
    require 'bundler'
    Bundler.require
    require 'rails/all'
    require 'newrelic_rpm'

    # Bootstrap a basic rails environment for the agent to run in.
    class MyApp < Rails::Application
      config.active_support.deprecation = :log
      config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
      config.after_initialize do
        NewRelic::Agent.manual_start
      end
    end
    MyApp.initialize!
  end
end

require 'test/unit'
begin
  require 'mocha/setup'
rescue LoadError
  require 'mocha'
end

begin # 1.8.6
  require 'mocha/integration/test_unit'
  require 'mocha/integration/test_unit/assertion_counter'
rescue LoadError
end

require 'agent_helper'

def default_service(stubbed_method_overrides = {})
  service = stub
  stubbed_method_defaults = {
    :connect => {},
    :shutdown => nil,
    :agent_id= => nil,
    :agent_id => nil,
    :collector => stub_everything,
    :request_timeout= =>  nil,
    :metric_data => nil,
    :error_data => nil,
    :transaction_sample_data => nil,
    :sql_trace_data => nil,
    :get_agent_commands => [],
    :agent_command_results => nil,
    :analytic_event_data => nil
  }

  service.stubs(stubbed_method_defaults.merge(stubbed_method_overrides))

  # When session gets called yield to the given block.
  service.stubs(:session).yields
  service
end

class Test::Unit::TestCase
  include Mocha::API

  # we can delete this trick when we stop supporting rails2.0.x
  if ENV['BRANCH'] != 'rails20'
    # a hack because rails2.0.2 does not like double teardowns
    def teardown
      mocha_teardown
    end
  end
end

def with_verbose_logging
  orig_logger = NewRelic::Agent.logger
  $stderr.puts '', '---', ''
  new_logger = NewRelic::Agent::AgentLogger.new( {:log_level => 'debug'}, '', Logger.new($stderr) )
  NewRelic::Agent.logger = new_logger

  yield

ensure
  NewRelic::Agent.logger = orig_logger
end

# Need to be a bit sloppy when testing against the logging--let everything
# through, but check we (at least) get our particular message we care about
def expects_logging(level, *with_params)
  ::NewRelic::Agent.logger.stubs(level)
  ::NewRelic::Agent.logger.expects(level).with(*with_params).once
end

def expects_no_logging(level)
  ::NewRelic::Agent.logger.expects(level).never
end

# Sometimes need to test cases where we muddle with the global logger
# If so, use this method to ensure it gets restored after we're done
def without_logger
  logger = ::NewRelic::Agent.logger
  ::NewRelic::Agent.logger = nil
  yield
ensure
  ::NewRelic::Agent.logger = logger
end

def fixture_tcp_socket( response )
  # Don't actually talk to Google.
  socket = stub("socket") do
    stubs(:closed?).returns(false)
    stubs(:close)
    stubs(:setsockopt)

    # Simulate a bunch of socket-ey stuff since Mocha doesn't really
    # provide any other way to do it
    class << self
      attr_accessor :response, :write_checker
    end

    def self.check_write
      self.write_checker = Proc.new
    end

    def self.write( buf )
      self.write_checker.call( buf ) if self.write_checker
      buf.length
    end

    def self.sysread( size, buf='' )
      @data ||= response.to_s
      raise EOFError if @data.empty?
      buf.replace @data.slice!( 0, size )
      buf
    end
    class << self
      alias_method :read_nonblock, :sysread
    end

  end

  socket.response = response
  TCPSocket.stubs( :open ).returns( socket )

  return socket
end


class ArrayLogDevice
  def initialize( array=[] )
    @array = array
  end
  attr_reader :array

  def write( message )
    @array << message
  end

  def close; end
end

def with_array_logger( level=:info )
  orig_logger = NewRelic::Agent.logger
  config = {
      :log_file_path => nil,
      :log_file_name => nil,
      :log_level => level,
    }
  logdev = ArrayLogDevice.new
  override_logger = Logger.new( logdev )
  NewRelic::Agent.logger = NewRelic::Agent::AgentLogger.new(config, "", override_logger)

  yield

  return logdev
ensure
  NewRelic::Agent.logger = orig_logger
end


module TransactionSampleTestHelper
  module_function
  def make_sql_transaction(*sql)
    sampler = NewRelic::Agent::TransactionSampler.new
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction(nil, :jim => "cool")
    sampler.notice_push_scope "a"
    explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
    sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "test"}, 0, &explainer) }
    sleep 0.02
    yield if block_given?
    sampler.notice_pop_scope "a"
    sampler.notice_scope_empty(stub('txn', :name => '/path', :custom_parameters => {}))

    sampler.last_sample
  end

  def run_sample_trace_on(sampler, path='/path')
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction(path, {})
    sampler.notice_push_scope "Controller/sandwiches/index"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", {}, 0)
    sampler.notice_push_scope "ab"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", {}, 0)
    yield sampler if block_given?
    sampler.notice_pop_scope "ab"
    sampler.notice_push_scope "lew"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", {}, 0)
    sampler.notice_pop_scope "lew"
    sampler.notice_pop_scope "Controller/sandwiches/index"
    sampler.notice_scope_empty(stub('txn', :name => path, :custom_parameters => {}))
    sampler.last_sample
  end
end
