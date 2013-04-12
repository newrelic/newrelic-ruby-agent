# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel'

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::SequelInstrumentationTest < Test::Unit::TestCase
  require 'active_record_fixtures'
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  DB = Sequel.mock( :postgres )
  DB.extension :newrelic_instrumentation

  class Author < Sequel::Model( :authors )
  end
  class Post < Sequel::Model( :posts )
  end

  def setup
    $stderr.puts '', '---', ''
    NewRelic::Agent.logger =
      NewRelic::Agent::AgentLogger.new( {:log_level => 'debug'}, '', Logger.new($stderr) )

    super

    NewRelic::Agent.manual_start

    @agent = NewRelic::Agent.instance
    @agent.transaction_sampler.reset!

    @engine = @agent.stats_engine
    @engine.clear_stats
    @engine.start_transaction( 'test' )

    @sampler = NewRelic::Agent.instance.transaction_sampler
    @sampler.notice_first_scope_push( Time.now.to_f )
    @sampler.notice_transaction( '/path', '/path', {} )
    @sampler.notice_push_scope "Controller/sandwiches/index"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", nil, 0)
    @sampler.notice_push_scope "ab"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", nil, 0)
    @sampler.notice_push_scope "fetch_external_service"
  end

  def teardown
    super
    @engine.end_transaction
    NewRelic::Agent::TransactionInfo.reset
    Thread::current[:newrelic_scope_name] = nil
    NewRelic::Agent.shutdown
  end


  def test_sequel_instrumentation_is_loaded
    assert DB.respond_to?( :primary_metric_for )
  end

  def test_dataset_enumerator_generates_metrics
    Post.all

    assert_includes DB.sqls, 'SELECT * FROM posts'
    assert_includes @engine.metrics, 'ActiveRecord/Post/select'
  end

end


