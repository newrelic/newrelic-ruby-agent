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

require 'minitest/autorun'
require 'mocha/setup'

unless defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

require 'hometown'
Hometown.watch(::Thread)

# Set up a watcher for leaking agent threads out of tests.  It'd be nice to
# disable the threads everywhere, but not all tests have newrelic.yml loaded to
# us to rely on, so instead we'll just watch for it.
class Minitest::Test
  def before_setup
    if self.respond_to?(:name)
      test_method_name = self.name
    else
      test_method_name = self.__name__
    end

    NewRelic::Agent.logger.info("*** #{self.class}##{test_method_name} **")

    @__thread_count = ruby_threads.count
    super
  end

  def after_teardown
    unfreeze_time

    threads = ruby_threads
    if @__thread_count != threads.count
      backtraces = threads.map do |thread|
        trace = Hometown.for(thread)
        trace.backtrace.join("\n    ")
      end.join("\n\n")

      fail "Thread count changed in this test from #{@__thread_count} to #{threads.count}\n#{backtraces}"
    end

    super
  end

  # We only want to count threads that were spun up from Ruby (i.e.
  # Thread.new) JRuby has system threads we don't care to track.
  def ruby_threads
    Thread.list.select { |t| Hometown.for(t) }
  end
end

Dir.glob('test/helpers/*').each { |f| require f }

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
    require 'newrelic_rpm'
  rescue LoadError
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

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper

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
    :analytic_event_data => nil,
    :valid_to_marshal? => true
  }

  service.stubs(stubbed_method_defaults.merge(stubbed_method_overrides))

  # When session gets called yield to the given block.
  service.stubs(:session).yields
  service
end

def with_verbose_logging
  orig_logger = NewRelic::Agent.logger
  $stderr.puts '', '---', ''
  new_logger = NewRelic::Agent::AgentLogger.new('', Logger.new($stderr) )
  NewRelic::Agent.logger = new_logger

  with_config(:log_level => 'debug') do
    yield
  end
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

def dummy_mysql_explain_result(hash=nil)
  hash ||= {
    'Id' => '1',
    'Select Type' => 'SIMPLE',
    'Table' => 'sandwiches',
    'Type' => 'range',
    'Possible Keys' => 'PRIMARY',
    'Key' => 'PRIMARY',
    'Key Length' => '4',
    'Ref' => '',
    'Rows' => '1',
    'Extra' => 'Using index'
  }
  explain_result = mock('explain result')
  explain_result.stubs(:each_hash).yields(hash)
  explain_result
end

module TransactionSampleTestHelper
  module_function
  def make_sql_transaction(*sql)
    sampler = nil
    state = NewRelic::Agent::TransactionState.tl_get

    in_transaction('/path') do
      sampler = NewRelic::Agent.instance.transaction_sampler
      sampler.notice_push_frame(state, "a")
      explainer = NewRelic::Agent::Instrumentation::ActiveRecord::EXPLAINER
      sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "mysql"}, 0, state, explainer) }
      sleep 0.02
      yield if block_given?
      sampler.notice_pop_frame(state, "a")
    end

    return sampler.last_sample
  end

  def run_sample_trace(path='/path')
    sampler = nil
    state = NewRelic::Agent::TransactionState.tl_get

    request = stub(:path => path)

    in_transaction("Controller/sandwiches/index", :request => request) do
      sampler = NewRelic::Agent.instance.transaction_sampler
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", {}, 0, state)
      sampler.notice_push_frame(state, "ab")
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", {}, 0, state)
      yield sampler if block_given?
      sampler.notice_pop_frame(state, "ab")
      sampler.notice_push_frame(state, "lew")
      sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", {}, 0, state)
      sampler.notice_pop_frame(state, "lew")
    end

    return sampler.last_sample
  end
end
