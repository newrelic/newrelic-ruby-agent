# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/mongodb_command_subscriber'

class NewRelic::Agent::Instrumentation::MongodbCommandSubscriberTest < Minitest::Test

  if RUBY_VERSION > "1.9.3"
    def setup
      freeze_time
      @started_event = mock('started event')
      @started_event.stubs(:operation_id).returns(1)
      @started_event.stubs(:command_name).returns('find')
      @started_event.stubs(:database_name).returns('mongodb-test')
      @started_event.stubs(:command).returns({ 'find' => 'users', 'filter' => { 'name' => 'test' }})
      address = stub('address', :host => "127.0.0.1", :port => 27017)
      @started_event.stubs(:address).returns(address)

      @succeeded_event = mock('succeeded event')
      @succeeded_event.stubs(:operation_id).returns(1)
      @succeeded_event.stubs(:duration).returns(2)

      @subscriber = NewRelic::Agent::Instrumentation::MongodbCommandSubscriber.new

      NewRelic::Agent::Hostname.stubs(:get).returns("nerd-server")
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

    def test_records_instance_metrics_for_tcp_connection
      simulate_query
      assert_metrics_recorded('Datastore/instance/MongoDB/nerd-server/27017')
    end

    def test_records_instance_metrics_for_unix_domain_socket
      address = stub('address', :host => "/tmp/mongodb-27017.sock", :port => nil)
      @started_event.stubs(:address).returns(address)
      simulate_query
      assert_metrics_recorded('Datastore/instance/MongoDB/nerd-server//tmp/mongodb-27017.sock')
    end

    def test_records_unknown_unknown_metric_when_error_gathering_instance_data
      @started_event.stubs(:address).returns(nil)
      simulate_query
      assert_metrics_recorded('Datastore/instance/MongoDB/unknown/unknown')
    end

    def test_records_tt_segment_parameters_for_datastore_instance
      in_transaction do
        simulate_query
      end

      tt = last_transaction_trace

      node = find_node_with_name_matching tt, /^Datastore\//

      assert_equal(NewRelic::Agent::Hostname.get, node[:host])
      assert_equal('27017', node[:port_path_or_id])
      assert_equal('mongodb-test', node[:database_name])
    end



    def simulate_query
      @subscriber.started(@started_event)
      advance_time @succeeded_event.duration
      @subscriber.succeeded(@succeeded_event)
    end
  end
end
