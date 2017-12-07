# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/transaction'

module NewRelic
  module Agent
    class DatastoreApiTest < Minitest::Test
      def setup
        frozen_time
        NewRelic::Agent.drop_buffered_data
      end

      load_cross_agent_test('datastores/datastore_api').each do |test|
        define_method :"test_#{test['test_name'].tr(' ', '_')}" do
          NewRelic::Agent::Hostname.stubs(:get).returns(test['input']['system_hostname'])

          params = test['input']['parameters']
          txn_helper_method = test['input']['is_web'] ? :in_web_transaction : :in_background_transaction
          config = test['input']['configuration'].merge(:disable_harvest_thread => true)

          with_config config do
            send(txn_helper_method) do
              segment = NewRelic::Agent::Transaction.start_datastore_segment(
                product: params['product'],
                operation: params['operation'],
                collection: params['collection'],
                host: params['host'],
                port_path_or_id: params['port_path_or_id'],
                database_name: params['database_name']
              )
              segment.notice_sql "select * from foo"
              advance_time 2.0
              segment.finish
            end

            host, port_path_or_id, database_name =
              test['expectation']['transaction_segment_and_slow_query_trace'].values_at('host', 'port_path_or_id', 'database_name')

            segment_name = test['expectation']['metrics_scoped'][0]

            assert_metrics_recorded test['expectation']['metrics_unscoped']
            assert_expected_tt_segment_params segment_name, host, port_path_or_id, database_name
            assert_expected_slow_sql_params host, port_path_or_id, database_name
          end
        end
      end

      def assert_expected_tt_segment_params segment_name, host, port_path_or_id, database_name
        trace = last_transaction_trace
        segment = find_node_with_name trace, segment_name

        assert_equal host, segment[:host]
        assert_equal port_path_or_id, segment[:port_path_or_id]
        assert_equal database_name, segment[:database_name]
      end

      def assert_expected_slow_sql_params host, port_path_or_id, database_name
        sql_trace = last_sql_trace

        assert_equal host, sql_trace.params[:host]
        assert_equal port_path_or_id, sql_trace.params[:port_path_or_id]
        assert_equal database_name, sql_trace.params[:database_name]
      end
    end
  end
end
