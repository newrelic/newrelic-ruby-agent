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
# We can speed things up in tests that don't need to load rails.
# You can also run the tests in a mode without rails.  Many tests
# will be skipped.

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

require 'test/unit'
require 'shoulda'
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
    :get_agent_commands => []
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

def assert_between(floor, ceiling, value, message="expected #{floor} <= #{value} <= #{ceiling}")
  assert((floor <= value && value <= ceiling), message)
end

def check_metric_time(metric, value, delta)
  time = NewRelic::Agent.get_stats(metric).total_call_time
  assert_between((value - delta), (value + delta), time)
end

def check_metric_count(metric, value)
  count = NewRelic::Agent.get_stats(metric).call_count
  assert_equal(value, count, "should have the correct number of calls")
end

def check_unscoped_metric_count(metric, value)
  count = NewRelic::Agent.get_stats_unscoped(metric).call_count
  assert_equal(value, count, "should have the correct number of calls")
end

def generate_unscoped_metric_counts(*metrics)
  metrics.inject({}) do |sum, metric|
    sum[metric] = NewRelic::Agent.get_stats_no_scope(metric).call_count
    sum
  end
end

def generate_metric_counts(*metrics)
  metrics.inject({}) do |sum, metric|
    sum[metric] = NewRelic::Agent.get_stats(metric).call_count
    sum
  end
end

def assert_does_not_call_metrics(*metrics)
  first_metrics = generate_metric_counts(*metrics)
  yield
  last_metrics = generate_metric_counts(*metrics)
  assert_equal first_metrics, last_metrics, "should not have changed these metrics"
end

def assert_calls_metrics(*metrics)
  first_metrics = generate_metric_counts(*metrics)
  yield
  last_metrics = generate_metric_counts(*metrics)
  assert_not_equal first_metrics, last_metrics, "should have changed these metrics"
end

def assert_calls_unscoped_metrics(*metrics)
  first_metrics = generate_unscoped_metric_counts(*metrics)
  yield
  last_metrics = generate_unscoped_metric_counts(*metrics)
  assert_not_equal first_metrics, last_metrics, "should have changed these metrics"
end

unless defined?( assert_includes )
  def assert_includes( collection, member, msg=nil )
    msg = build_message( msg, "Expected ? to include ?", collection, member )
    assert_block( msg ) { collection.include?(member) }
  end
end

unless defined?( assert_not_includes )
  def assert_not_includes( collection, member, msg=nil )
    msg = build_message( msg, "Expected ? not to include ?", collection, member )
    assert_block( msg ) { !collection.include?(member) }
  end
end

def compare_metrics(expected, actual)
  actual.delete_if {|a| a.include?('GC/cumulative') } # in case we are in REE
  assert_equal(expected.to_a.sort, actual.to_a.sort, "extra: #{(actual - expected).to_a.inspect}; missing: #{(expected - actual).to_a.inspect}")
end

def metric_spec_from_specish(specish)
  spec = case specish
  when String then NewRelic::MetricSpec.new(specish)
  when Array  then NewRelic::MetricSpec.new(*specish)
  end
  spec
end

def _normalize_metric_expectations(expectations)
  case expectations
  when Array
    hash = {}
    expectations.each { |k| hash[k] = { :call_count => 1 } }
    hash
  else
    expectations
  end
end

def assert_metrics_recorded(expected)
  expected = _normalize_metric_expectations(expected)
  expected.each do |specish, expected_attrs|
    expected_spec = metric_spec_from_specish(specish)
    actual_stats = NewRelic::Agent.instance.stats_engine.lookup_stats(*Array(specish))
    if !actual_stats
      all_specs = NewRelic::Agent.instance.stats_engine.metric_specs
      matches = all_specs.select { |spec| spec.name == expected_spec.name }
      matches.map! { |m| "  #{m.inspect}" }
      msg = "Did not find stats for spec #{expected_spec.inspect}."
      msg += "\nDid find specs: [\n#{matches.join(",\n")}\n]" unless matches.empty?
      assert(actual_stats, msg)
    end
    expected_attrs.each do |attr, expected_value|
      actual_value = actual_stats.send(attr)
      assert_equal(expected_value, actual_value,
        "Expected #{attr} for #{expected_spec} to be #{expected_value}, got #{actual_value}")
    end
  end
end

def assert_metrics_recorded_exclusive(expected)
  expected = _normalize_metric_expectations(expected)
  assert_metrics_recorded(expected)
  recorded_metrics = NewRelic::Agent.instance.stats_engine.metrics
  expected_metrics = expected.keys.map { |s| metric_spec_from_specish(s).to_s }
  unexpected_metrics = recorded_metrics.select{|m| m !~ /GC\/cumulative/}
  unexpected_metrics -= expected_metrics
  assert_equal(0, unexpected_metrics.size, "Found unexpected metrics: [#{unexpected_metrics.join(', ')}]")
end

def with_config(config_hash, opts={})
  opts = { :level => 0, :do_not_cast => false }.merge(opts)
  if opts[:do_not_cast]
    config = config_hash
  else
    config = NewRelic::Agent::Configuration::DottedHash.new(config_hash)
  end
  NewRelic::Agent.config.apply_config(config, opts[:level])
  begin
    yield
  ensure
    NewRelic::Agent.config.remove_config(config)
  end
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

def in_transaction(name='dummy')
  NewRelic::Agent.instance.instance_variable_set(:@transaction_sampler,
                        NewRelic::Agent::TransactionSampler.new)
  NewRelic::Agent.instance.stats_engine.transaction_sampler = \
    NewRelic::Agent.instance.transaction_sampler
  txn = NewRelic::Agent::Instrumentation::Transaction.current(true)
  txn.filtered_params = {}
  txn.start(:other)
  txn.start_transaction
  val = yield
  txn.stop(name)
  val
end

def freeze_time(now=Time.now)
  Time.stubs(:now).returns(now)
end

def advance_time(seconds)
  freeze_time(Time.now + seconds)
end

module NewRelic
  def self.fixture_path(name)
    File.join(File.dirname(__FILE__), 'fixtures', name)
  end
end

def fixture_tcp_socket( response )
  # Don't actually talk to Google.
  socket = stub("socket") do
    stubs(:closed?).returns(false)
    stubs(:close)

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

module TransactionSampleTestHelper
  module_function
  def make_sql_transaction(*sql)
    sampler = NewRelic::Agent::TransactionSampler.new
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction(nil, :jim => "cool")
    sampler.notice_push_scope "a"
    sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "test"}, 0 ) }

    sleep 0.02
    yield if block_given?
    sampler.notice_pop_scope "a"
    sampler.notice_scope_empty('/path/2')

    sampler.samples[0]
  end

  def run_sample_trace_on(sampler, path='/path')
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction(path, {})
    sampler.notice_push_scope "Controller/sandwiches/index"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", nil, 0)
    sampler.notice_push_scope "ab"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", nil, 0)
    yield sampler if block_given?
    sampler.notice_pop_scope "ab"
    sampler.notice_push_scope "lew"
    sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", nil, 0)
    sampler.notice_pop_scope "lew"
    sampler.notice_pop_scope "Controller/sandwiches/index"
    sampler.notice_scope_empty(path)
    sampler.samples[0]
  end
end
