# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::MetricFrameTest < Test::Unit::TestCase

  attr_reader :f
  def setup
    @f = NewRelic::Agent::Instrumentation::MetricFrame.new
  end

  def test_request_parsing__none
    assert_nil f.uri
    assert_nil f.referer
  end
  def test_request_parsing__path
    request = stub(:path => '/path?hello=bob#none')
    f.request = request
    assert_equal "/path", f.uri
  end
  def test_request_parsing__fullpath
    request = stub(:fullpath => '/path?hello=bob#none')
    f.request = request
    assert_equal "/path", f.uri
  end
  def test_request_parsing__referer
    request = stub(:referer => 'https://www.yahoo.com:8080/path/hello?bob=none&foo=bar')
    f.request = request
    assert_nil f.uri
    assert_equal "https://www.yahoo.com:8080/path/hello", f.referer
  end

  def test_request_parsing__uri
    request = stub(:uri => 'http://creature.com/path?hello=bob#none', :referer => '/path/hello?bob=none&foo=bar')
    f.request = request
    assert_equal "/path", f.uri
    assert_equal "/path/hello", f.referer
  end

  def test_request_parsing__hostname_only
    request = stub(:uri => 'http://creature.com')
    f.request = request
    assert_equal "/", f.uri
    assert_nil f.referer
  end
  def test_request_parsing__slash
    request = stub(:uri => 'http://creature.com/')
    f.request = request
    assert_equal "/", f.uri
    assert_nil f.referer
  end

  def test_queue_time
    f.apdex_start = 1000
    f.start = 1500
    assert_equal 500, f.queue_time
  end

  def test_update_apdex_records_failed_when_specified
    stats = NewRelic::Agent::Stats.new
    NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.1, true)
    assert_equal 0, stats.apdex_s
    assert_equal 0, stats.apdex_t
    assert_equal 1, stats.apdex_f
  end

  def test_update_apdex_records_satisfying
    stats = NewRelic::Agent::Stats.new
    with_config(:apdex_t => 1) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.5, false)
    end
    assert_equal 1, stats.apdex_s
    assert_equal 0, stats.apdex_t
    assert_equal 0, stats.apdex_f
  end

  def test_update_apdex_records_tolerating
    stats = NewRelic::Agent::Stats.new
    with_config(:apdex_t => 1) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 1.5, false)
    end
    assert_equal 0, stats.apdex_s
    assert_equal 1, stats.apdex_t
    assert_equal 0, stats.apdex_f
  end

  def test_update_apdex_records_failing
    stats = NewRelic::Agent::Stats.new
    with_config(:apdex_t => 1) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 4.5, false)
    end
    assert_equal 0, stats.apdex_s
    assert_equal 0, stats.apdex_t
    assert_equal 1, stats.apdex_f
  end

  def test_update_apdex_records_correct_apdex_for_key_transaction
    txn_info = NewRelic::Agent::TransactionInfo.get
    stats = NewRelic::Agent::Stats.new
    config = {
      :web_transactions_apdex => {
        'Controller/slow/txn' => 4,
        'Controller/fast/txn' => 0.1,
      },
      :apdex => 1
    }

    txn_info.transaction_name = 'Controller/slow/txn'
    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 3.5, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 5.5, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 16.5, false)
    end
    assert_equal 1, stats.apdex_s
    assert_equal 1, stats.apdex_t
    assert_equal 1, stats.apdex_f

    txn_info.transaction_name = 'Controller/fast/txn'
    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.05, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.2, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.5, false)
    end
    assert_equal 2, stats.apdex_s
    assert_equal 2, stats.apdex_t
    assert_equal 2, stats.apdex_f

    txn_info.transaction_name = 'Controller/other/txn'
    with_config(config, :do_not_cast => true) do
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 0.5, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 2, false)
      NewRelic::Agent::Instrumentation::MetricFrame.update_apdex(stats, 5, false)
    end
    assert_equal 3, stats.apdex_s
    assert_equal 3, stats.apdex_t
    assert_equal 3, stats.apdex_f
  end

  def test_record_apdex_stores_apdex_t_in_min_and_max
    stats_engine = NewRelic::Agent.instance.stats_engine
    stats_engine.reset_stats
    metric = stub(:apdex_metric_path => 'Apdex/Controller/some/txn')
    NewRelic::Agent.instance.instance_variable_set(:@stats_engine, stats_engine)

    with_config(:apdex_t => 2.5) do
      NewRelic::Agent::Instrumentation::MetricFrame.record_apdex(metric, 1, 1, false)
    end
    assert_equal 2.5, stats_engine.lookup_stats('Apdex').min_call_time
    assert_equal 2.5, stats_engine.lookup_stats('Apdex').max_call_time
    assert_equal 2.5, stats_engine.lookup_stats('Apdex/Controller/some/txn').min_call_time
    assert_equal 2.5, stats_engine.lookup_stats('Apdex/Controller/some/txn').max_call_time
  end
end
