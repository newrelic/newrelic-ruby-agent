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
  begin
    require 'test_help'
  rescue LoadError
    # ignore load problems on test help - it doesn't exist in rails 3
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
require 'test_contexts'
require 'mocha'

begin # 1.8.6
  require 'mocha/integration/test_unit'
  require 'mocha/integration/test_unit/assertion_counter'
rescue LoadError
end

require 'new_relic/fake_service'

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


def compare_metrics(expected, actual)
  actual.delete_if {|a| a.include?('GC/cumulative') } # in case we are in REE
  assert_equal(expected.to_a.sort, actual.to_a.sort, "extra: #{(actual - expected).to_a.inspect}; missing: #{(expected - actual).to_a.inspect}")
end

def with_config(config_hash, level=0)
  config = NewRelic::Agent::Configuration::DottedHash.new(config_hash)
  NewRelic::Agent.config.apply_config(config, level)
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

# Similarly, have to be specific about the message we "never" expect...
def expects_no_logging(level, *with_params)
  ::NewRelic::Agent.logger.stubs(level)
  ::NewRelic::Agent.logger.expects(level).with(*with_params).never
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

module NewRelic
  def self.fixture_path(name)
    File.join(File.dirname(__FILE__), 'fixtures', name)
  end
end

module TransactionSampleTestHelper
  module_function
  def make_sql_transaction(*sql)
    sampler = NewRelic::Agent::TransactionSampler.new
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction '/path', nil, :jim => "cool"
    sampler.notice_push_scope "a"

    sampler.notice_transaction '/path/2', nil, :jim => "cool"

    sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "test"}, 0 ) }

    sleep 0.02
    yield if block_given?
    sampler.notice_pop_scope "a"
    sampler.notice_scope_empty

    sampler.samples[0]
  end

  def run_sample_trace_on(sampler, path='/path')
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction path, path, {}
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
    sampler.notice_scope_empty
    sampler.samples[0]
  end
end
