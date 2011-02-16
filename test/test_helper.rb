module NewRelic; TEST = true; end unless defined? NewRelic::TEST
ENV['RAILS_ENV'] = 'test'
NEWRELIC_PLUGIN_DIR = File.expand_path(File.join(File.dirname(__FILE__),".."))
$LOAD_PATH << '.'
$LOAD_PATH << '../../..'
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"test")
$LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR,"ui/helpers")
$LOAD_PATH.uniq!

require 'rubygems'
# We can speed things up in tests that don't need to load rails.
# You can also run the tests in a mode without rails.  Many tests 
# will be skipped.
if ENV['SKIP_RAILS']
  dirs = File.dirname(__FILE__).split('/')
  while dirs.any? && !File.directory?((dirs+%w[log]).join('/'))
    dirs.pop
  end
  RAILS_ROOT = dirs.any? ? dirs.join("/") : "#{File.dirname(__FILE__)}/.." unless defined?(RAILS_ROOT)
  $LOAD_PATH << File.join(NEWRELIC_PLUGIN_DIR, "lib")
  require File.join(NEWRELIC_PLUGIN_DIR, "lib/newrelic_rpm")
else
  begin
    require 'config/environment'
    begin
      require 'test_help'
    rescue LoadError
      # ignore load problems on test help - it doesn't exist in rails 3
    end
    
  rescue LoadError
    puts "Unable to load Rails for New Relic tests: try setting the environment variable SKIP_RAILS=false"
    raise
  end
end
require 'new_relic/agent'
NewRelic::Agent.manual_start
require 'test/unit'
require 'shoulda'
require 'test_contexts'
require 'mocha'
require 'mocha/integration/test_unit'
require 'mocha/integration/test_unit/assertion_counter'
class Test::Unit::TestCase
  include Mocha::API

  # FIXME delete this trick when we stop supporting rails2.0.x
  if ENV['BRANCH'] != 'rails20'
    # a hack because rails2.0.2 does not like double teardowns
    def teardown
      mocha_teardown
    end
  end
end

def assert_between(floor, ceiling, value, message = nil)
  assert floor <= value && value <= ceiling,
  message || "expected #{floor} <= #{value} <= #{ceiling}"
end

def compare_metrics expected_list, actual_list
  actual = Set.new actual_list
  actual.delete('GC/cumulative') # in case we are in REE
  expected = Set.new expected_list
  assert_equal expected.to_a.sort, actual.to_a.sort, "extra: #{(actual - expected).to_a.join(", ")}; missing: #{(expected - actual).to_a.join(", ")}"
end
=begin Enable this to see test names as they run
Test::Unit::TestCase.class_eval do
  def run_with_info *args, &block
    puts "#{self.class.name.underscore}/#{@method_name}"
    run_without_info *args, &block
  end
  alias_method_chain :run, :info
end
=end
module TransactionSampleTestHelper
  def make_sql_transaction(*sql)
    sampler = NewRelic::Agent::TransactionSampler.new
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction '/path', nil, :jim => "cool"
    sampler.notice_push_scope "a"
    
    sampler.notice_transaction '/path/2', nil, :jim => "cool"
    
    sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "test"}, 0 ) }
    
    sleep 1.0
    yield if block_given?
    sampler.notice_pop_scope "a"
    sampler.notice_scope_empty
    
    sampler.samples[0]
  end
end
