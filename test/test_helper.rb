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

module TransactionSampleTestHelper
  def make_sql_transaction(*sql)
    sampler = NewRelic::Agent::TransactionSampler.new(NewRelic::Agent.instance)
    sampler.notice_first_scope_push Time.now.to_f
    sampler.notice_transaction '/path', nil, :jim => "cool"
    sampler.notice_push_scope "a"
    
    sampler.notice_transaction '/path/2', nil, :jim => "cool"
    
    sql.each {|sql_statement| sampler.notice_sql(sql_statement, {:adapter => "test"}, 0 ) }
    
    sleep 1.0
    
    sampler.notice_pop_scope "a"
    sampler.notice_scope_empty
    
    sampler.samples[0]
  end
end
