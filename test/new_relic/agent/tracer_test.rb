# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic
  module Agent
    class TracerTest < Minitest::Test
      def test_tracer_aliases
        trace_state = Tracer.trace_state
        refute_nil trace_state
      end

      def test_current_transaction_with_transaction
        in_transaction do |txn|
          assert_equal txn, Tracer.current_transaction
        end
      end

      def test_current_transaction_without_transaction
        assert_nil Tracer.current_transaction
      end

      def test_tracing_enabled
        NewRelic::Agent.disable_all_tracing do
          in_transaction do
            NewRelic::Agent.disable_all_tracing do
              refute Tracer.tracing_enabled?
            end
            refute Tracer.tracing_enabled?
          end
        end
        assert Tracer.tracing_enabled?
      end

      def test_start_transaction_without_one_already_existing
        assert_nil Tracer.current_transaction

        txn = Tracer.start_transaction(name: "Controller/Blogs/index",
                                       category: :controller)

        assert_equal txn, Tracer.current_transaction

        txn.stop
        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_returns_current_if_aready_in_progress
        in_transaction do |txn1|
          refute_nil Tracer.current_transaction

          txn2 = Tracer.start_transaction(name: "Controller/Blogs/index",
                                         category: :controller)

          assert_equal txn2, txn1
          assert_equal txn2, Tracer.current_transaction
        end
      end

      def test_start_segment_delegates_to_transaction
        name = "Custom/MyClass/myoperation"
        unscoped_metrics = [
          "Custom/Segment/something/all",
          "Custom/Segment/something/allWeb"
        ]
        parent = Tracer.start_segment(name: "parent")
        start_time = Time.now

        Transaction.expects(:start_segment).with(name: name,
                                                 unscoped_metrics: unscoped_metrics,
                                                 parent: parent,
                                                 start_time: start_time)

        Tracer.start_segment(name: name,
                             unscoped_metrics: unscoped_metrics,
                             parent: parent,
                             start_time: start_time)
      end

      def test_start_datastore_segment_delegates_to_transaction
        product         = "MySQL"
        operation       = "INSERT"
        collection      = "blogs"
        host            = "localhost"
        port_path_or_id = "3306"
        database_name   = "blog_app"
        start_time      = Time.now
        parent          = Tracer.start_segment(name: "parent")

        Transaction.expects(:start_datastore_segment)
                   .with(product: product,
                         operation: operation,
                         collection: collection,
                         host: host,
                         port_path_or_id: port_path_or_id,
                         database_name: database_name,
                         start_time: start_time,
                         parent: parent)

        Transaction.start_datastore_segment(product: product,
                                            operation: operation,
                                            collection: collection,
                                            host: host,
                                            port_path_or_id: port_path_or_id,
                                            database_name: database_name,
                                            start_time: start_time,
                                            parent: parent)
      end
    end
  end
end
