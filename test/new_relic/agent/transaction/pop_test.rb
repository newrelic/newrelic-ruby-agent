# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/transaction/pop'
class NewRelic::Agent::Transaction::PopTest < Test::Unit::TestCase
  include NewRelic::Agent::Transaction::Pop

  attr_reader :agent
  attr_reader :transaction_sampler
  attr_reader :sql_sampler

  def setup
    @transaction_type_stack = []
    @agent = mock('agent')
    @transaction_sampler = mock('transaction sampler')
    @sql_sampler = mock('sql sampler')
  end

  def test_log_underflow
    expects_logging(:error, regexp_matches(/Underflow in transaction: /))
    log_underflow
  end

  def test_record_transaction_cpu_positive
    self.expects(:cpu_burn).once.returns(1.0)
    transaction_sampler.expects(:notice_transaction_cpu_time).with(1.0)
    record_transaction_cpu
  end

  def test_record_transaction_cpu_negative
    self.expects(:cpu_burn).once.returns(nil)
    # should not be called for the nil case
    transaction_sampler.expects(:notice_transaction_cpu_time).never
    record_transaction_cpu
  end

  def test_normal_cpu_burn_positive
    @process_cpu_start = 3
    self.expects(:process_cpu).returns(4)
    assert_equal 1, normal_cpu_burn
  end

  def test_normal_cpu_burn_negative
    @process_cpu_start = nil
    self.expects(:process_cpu).never
    assert_equal nil, normal_cpu_burn
  end

  def test_jruby_cpu_burn_negative
    @jruby_cpu_start = nil
    self.expects(:jruby_cpu_time).never
    self.expects(:record_jruby_cpu_burn).never
    assert_equal nil, jruby_cpu_burn
  end

  def test_record_jruby_cpu_burn
    NewRelic::Agent.get_stats_no_scope(NewRelic::Metrics::USER_TIME).expects(:record_data_point).with(1.0, 1.0)
    record_jruby_cpu_burn(1.0)
  end

  def test_cpu_burn_normal
    self.expects(:normal_cpu_burn).returns(1)
    self.expects(:jruby_cpu_burn).never
    assert_equal 1, cpu_burn
  end

  def test_cpu_burn_jruby
    self.expects(:normal_cpu_burn).returns(nil)
    self.expects(:jruby_cpu_burn).returns(2)
    assert_equal 2, cpu_burn
  end

  def test_current_stack_metric
    self.expects(:metric_name)
    current_stack_metric
  end
end
