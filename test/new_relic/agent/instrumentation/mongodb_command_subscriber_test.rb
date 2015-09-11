# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/mongodb_command_subscriber'

class NewRelic::Agent::Instrumentation::MongodbCommandSubscriberTest < Minitest::Test

  if RUBY_VERSION > "1.9.3"
    def setup
      @started_event = mock('started event')
      @started_event.stubs(:operation_id).returns(1)
      @started_event.stubs(:command_name).returns('find')
      @started_event.stubs(:database_name).returns('mongodb-test')
      @started_event.stubs(:command).returns({ 'find' => 'users', 'filter' => { 'name' => 'test' }})

      @succeeded_event = mock('succeeded event')
      @succeeded_event.stubs(:operation_id).returns(1)
      @succeeded_event.stubs(:duration).returns(2)

      @subscriber = NewRelic::Agent::Instrumentation::MongodbCommandSubscriber.new

      @stats_engine = NewRelic::Agent.instance.stats_engine
      @stats_engine.clear_stats
    end

    def test_records_metrics_for_simple_find
      simulate_query

      metric_name = 'Datastore/statement/MongoDB/users/find'
      assert_metrics_recorded(
        metric_name => { :call_count => 1, :total_call_time => 2.0 }
      )
    end

    def test_records_scoped_metrics
      in_transaction('test_txn') { simulate_query }

      metric_name = 'Datastore/statement/MongoDB/users/find'
      assert_metrics_recorded(
        [ metric_name, 'test_txn' ] => { :call_count => 1, :total_call_time => 2 }
      )
    end

    def test_records_nothing_if_tracing_disabled
      NewRelic::Agent.disable_all_tracing { simulate_query }
      metric_name = 'Datastore/statement/MongoDB/users/find'
      assert_metrics_not_recorded([ metric_name ])
    end

    def test_records_rollup_metrics
      in_web_transaction { simulate_query }

      assert_metrics_recorded(
        'Datastore/operation/MongoDB/find' => { :call_count => 1, :total_call_time => 2 },
        'Datastore/allWeb' => { :call_count => 1, :total_call_time => 2 },
        'Datastore/all' => { :call_count => 1, :total_call_time => 2 }
      )
    end

    def test_should_not_raise_due_to_an_exception_during_instrumentation_callback
      @subscriber.stubs(:metrics).raises(StandardError)
      simulate_query
    end

    def simulate_query
      @subscriber.started(@started_event)
      @subscriber.succeeded(@succeeded_event)
    end
  end
end
