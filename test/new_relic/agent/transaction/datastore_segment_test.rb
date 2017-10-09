# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction/datastore_segment'

module NewRelic
  module Agent
    class Transaction
      class DatastoreSegmentTest < Minitest::Test
        def setup
          freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_datastore_segment_name_with_collection
          segment = DatastoreSegment.new "SQLite", "insert", "Blog"
          assert_equal "Datastore/statement/SQLite/Blog/insert", segment.name
        end

        def test_datastore_segment_name_with_operation
          segment = DatastoreSegment.new "SQLite", "select"
          assert_equal "Datastore/operation/SQLite/select", segment.name
        end


        def test_segment_does_not_record_metrics_outside_of_txn
          segment = DatastoreSegment.new "SQLite", "insert", "Blog"
          segment.start
          advance_time 1
          segment.finish

          refute_metrics_recorded [
            "Datastore/statement/SQLite/Blog/insert",
            "Datastore/operation/SQLite/insert",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_records_expected_metrics
          in_web_transaction "text_txn" do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog"
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_recorded [
            "Datastore/statement/SQLite/Blog/insert",
            "Datastore/operation/SQLite/insert",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_records_expected_metrics_without_collection
          in_web_transaction "text_txn" do
            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_recorded [
            "Datastore/operation/SQLite/select",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_records_expected_metrics_with_instance_identifier
          in_web_transaction "text_txn" do
            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              host: "jonan-01",
              port_path_or_id: "1337807"
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_recorded [
            "Datastore/instance/SQLite/jonan-01/1337807",
            "Datastore/operation/SQLite/select",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_records_expected_metrics_with_instance_identifier_host_only
          in_web_transaction "text_txn" do
            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              host: "jonan-01"
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_recorded [
            "Datastore/instance/SQLite/jonan-01/unknown",
            "Datastore/operation/SQLite/select",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_records_expected_metrics_with_instance_identifier_port_only
          in_web_transaction "text_txn" do
            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              port_path_or_id: 1337807
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_recorded [
            "Datastore/instance/SQLite/unknown/1337807",
            "Datastore/operation/SQLite/select",
            "Datastore/SQLite/allWeb",
            "Datastore/SQLite/all",
            "Datastore/allWeb",
            "Datastore/all"
          ]
        end

        def test_segment_does_not_record_expected_metrics_with_empty_data
          in_web_transaction "text_txn" do
            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.start
            advance_time 1
            segment.finish
          end

          assert_metrics_not_recorded "Datastore/instance/SQLite/unknown/unknown"
        end

        def test_segment_does_not_record_instance_id_metrics_when_disabled
          with_config(:'datastore_tracer.instance_reporting.enabled' => false) do
            in_web_transaction "text_txn" do
              segment = Transaction.start_datastore_segment(
                product: "SQLite",
                operation: "select",
                collection: "jonan-01",
                port_path_or_id: "1337807"
              )
              segment.start
              advance_time 1
              segment.finish
            end

            assert_metrics_not_recorded "Datastore/instance/SQLite/jonan-01/1337807"
          end
        end

        def test_add_instance_identifier_segment_parameter
          segment = nil

          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              host: "jonan-01",
              port_path_or_id: "1337807"
            )
            advance_time 1
            segment.finish
          end

          sample = last_transaction_trace
          node = find_node_with_name(sample, segment.name)

          assert_equal "jonan-01", node.params[:host]
          assert_equal "1337807", node.params[:port_path_or_id]
        end

        def test_localhost_replaced_by_system_hostname
          NewRelic::Agent::Hostname.stubs(:get).returns("jonan.gummy_planet")

          %w[localhost 0.0.0.0 127.0.0.1 0:0:0:0:0:0:0:1 0:0:0:0:0:0:0:0 ::1 ::].each do |host|
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              collection: "blogs",
              host: host,
              port_path_or_id: "1337"
            )
            segment.finish

            assert_equal "jonan.gummy_planet", segment.host
          end
        end

        def test_does_not_add_instance_identifier_segment_parameter_when_disabled
          with_config(:'datastore_tracer.instance_reporting.enabled' => false) do
            segment = nil

            in_transaction do
              segment = NewRelic::Agent::Transaction.start_datastore_segment(
                product: "SQLite",
                operation: "select",
                host: "localhost",
                port_path_or_id: "1337807"
              )
              advance_time 1
              segment.finish
            end

            sample = last_transaction_trace
            node = find_node_with_name(sample, segment.name)

            refute node.params.key? :host
            refute node.params.key? :port_path_or_id
          end
        end

        def test_add_database_name_segment_parameter
          segment = nil

          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              database_name: "pizza_cube"
            )
            advance_time 1
            segment.finish
          end

          sample = last_transaction_trace
          node = find_node_with_name(sample, segment.name)

          assert_equal node.params[:database_name], "pizza_cube"
        end

        def test_does_not_add_database_name_segment_parameter_when_disabled
          with_config(:'datastore_tracer.database_name_reporting.enabled' => false) do
            segment = nil

            in_transaction do
              segment = NewRelic::Agent::Transaction.start_datastore_segment(
                product: "SQLite",
                operation: "select",
                database_name: "pizza_cube"
              )
              advance_time 1
              segment.finish
            end

            sample = last_transaction_trace
            node = find_node_with_name(sample, segment.name)

            refute node.params.key? :database_name
          end
        end

        def test_notice_sql
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.notice_sql "select * from blogs"
            advance_time 2.0
            Agent.instance.sql_sampler.expects(:notice_sql_statement) do |statement, name, duration|
              assert_equal segment.sql_statement.sql, statement.sql_statement
              assert_equal segment.name, name
              assert_equal duration, 2.0
            end
            segment.finish
            assert_equal segment.params[:sql].sql, "select * from blogs"
          end
        end

        def test_notice_sql_not_recording
          state = NewRelic::Agent::TransactionState.tl_get
          state.record_sql = false
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.notice_sql "select * from blogs"
            assert_nil segment.sql_statement
            segment.finish
          end
          state.record_sql = true
        end

        def test_notice_sql_creates_database_statement_with_identifier
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              host: "jonan.gummy_planet",
              port_path_or_id: "1337"
            )
            segment.notice_sql "select * from blogs"
            segment.finish

            assert_equal "jonan.gummy_planet", segment.sql_statement.host
            assert_equal "1337", segment.sql_statement.port_path_or_id
          end
        end

        def test_notice_sql_creates_database_statement_with_database_name
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select",
              database_name: "pizza_cube"
            )
            segment.notice_sql "select * from blogs"
            segment.finish

            assert_equal "pizza_cube", segment.sql_statement.database_name
          end
        end

        def test_notice_sql_truncates_long_queries
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.notice_sql "select * from blogs where " + ("something is nothing" * 16_384)
            segment.finish
            assert_equal segment.params[:sql].sql.length, 16_384
          end
        end

        def test_internal_notice_sql
          explainer = stub(:explainer)
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment._notice_sql "select * from blogs", {:adapter => :sqlite}, explainer
            advance_time 2.0
            Agent.instance.sql_sampler.expects(:notice_sql_statement) do |statement, name, duration|
              assert_equal segment.sql_statement.sql, statement.sql_statement
              assert_equal segment.name, name
              assert_equal duration, 2.0
            end
            segment.finish
            assert_equal segment.params[:sql].sql, "select * from blogs"
          end
        end

        def test_notice_nosql_statement
          statement = "set mykey 123"
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "Redis",
              operation: "set"
            )
            segment.notice_nosql_statement statement
            advance_time 2.0

            segment.finish
            assert_equal segment.params[:statement], statement
          end
        end

        def test_notice_nosql_statement_not_recording
          state = NewRelic::Agent::TransactionState.tl_get
          state.record_sql = false
          in_transaction do
            segment = NewRelic::Agent::Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "select"
            )
            segment.notice_nosql_statement "hgetall somehash"
            assert_nil segment.nosql_statement
            segment.finish
          end
          state.record_sql = true
        end

        def test_set_instance_info_with_valid_data
          segment = DatastoreSegment.new "SQLite", "select", nil
          segment.set_instance_info 'jonan.gummy_planet', 1337807
          assert_equal 'jonan.gummy_planet', segment.host
          assert_equal '1337807', segment.port_path_or_id
        end

        def test_set_instance_info_with_empty_host
          segment = DatastoreSegment.new "SQLite", "select", nil
          segment.set_instance_info nil, 1337807
          assert_equal 'unknown', segment.host
          assert_equal '1337807', segment.port_path_or_id
        end

        def test_set_instance_info_with_empty_port_path_or_id
          segment = DatastoreSegment.new "SQLite", "select", nil
          segment.set_instance_info 'jonan.gummy_planet', nil
          assert_equal 'jonan.gummy_planet', segment.host
          assert_equal 'unknown', segment.port_path_or_id
        end

        def test_set_instance_info_with_empty_data
          segment = DatastoreSegment.new "SQLite", "select", nil
          segment.set_instance_info nil, nil
          assert_nil segment.host
          assert_nil segment.port_path_or_id

          segment.set_instance_info '', ''
          assert_nil segment.host
          assert_nil segment.port_path_or_id
        end

        def test_backtrace_not_appended_if_not_over_duration
          segment = nil
          with_config :'transaction_tracer.stack_trace_threshold' => 2.0 do
            in_web_transaction "test_txn" do
              segment = NewRelic::Agent::Transaction.start_datastore_segment(
                product: "SQLite",
                operation: "insert",
                collection: "Blog"
              )
              segment.start
              advance_time 1.0
              segment.finish
            end
          end

          assert_nil segment.params[:backtrace]

          sample = last_transaction_trace
          node = find_node_with_name_matching(sample, /^Datastore/)
          assert_nil node.params[:backtrace]
        end

        def test_backtrace_appended_when_over_duration
          segment = nil
          with_config :'transaction_tracer.stack_trace_threshold' => 1.0 do
            in_web_transaction "test_txn" do
              segment = NewRelic::Agent::Transaction.start_datastore_segment(
                product: "SQLite",
                operation: "insert",
                collection: "Blog"
              )
              segment.start
              advance_time 2.0
              segment.finish
            end
          end

          refute_nil segment.params[:backtrace]

          sample = last_transaction_trace
          node = find_node_with_name_matching(sample, /^Datastore/)
          refute_nil node.params[:backtrace]
        end

        def test_node_obfuscated
          orig_sql = "SELECT * from Jim where id=66"

          in_transaction do
            s = NewRelic::Agent::Transaction.start_datastore_segment
            s.notice_sql(orig_sql)
            s.finish
          end
          node = find_last_transaction_node(last_transaction_trace)
          assert_equal orig_sql, node[:sql].sql
          assert_equal "SELECT * from Jim where id=?", node.obfuscated_sql
        end

        def test_sets_start_time_from_api
          t = Time.now

          in_transaction do |txn|

            segment = Transaction.start_datastore_segment(
              product: "SQLite",
              operation: "insert",
              collection: "Blog",
              start_time: t
            )
            segment.finish

            assert_equal t, segment.start_time
          end
        end
      end
    end
  end
end
