# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic
  module Agent
    class TracerTest < Minitest::Test
      def teardown
        NewRelic::Agent.instance.drop_buffered_data
      end

      def test_tracer_aliases
        state = Tracer.state
        refute_nil state
      end

      def test_current_transaction_with_transaction
        in_transaction do |txn|
          assert_equal txn, Tracer.current_transaction
        end
      end

      def test_current_transaction_without_transaction
        assert_nil Tracer.current_transaction
      end

      def test_trace_id_in_transaction
        in_transaction do |txn|
          refute_nil Tracer.trace_id
          assert_equal txn.trace_id, Tracer.trace_id
        end
      end

      def test_trace_id_not_in_transaction
        assert_nil Tracer.trace_id
      end

      def test_span_id_in_transaction
        in_transaction do |txn|
          refute_nil Tracer.span_id
          assert_equal txn.current_segment.guid, Tracer.span_id
        end
      end

      def test_span_id_not_in_transaction
        assert_nil Tracer.span_id
      end

      def test_sampled?
        with_config :'distributed_tracing.enabled' => true do
          in_transaction do |txn|
            refute_nil Tracer.sampled?
          end
          # with sampled explicity set true, assert that it's true
          in_transaction do |txn|
            txn.sampled = true
            assert Tracer.sampled?
          end
          # with sampled explicity set false, assert that it's false
          in_transaction do |txn|
            txn.sampled = false
            refute Tracer.sampled?
          end
        end

        with_config :'distributed_tracing.enabled' => false do
          in_transaction do |txn|
            assert_nil Tracer.sampled?
          end
        end
      end

      def test_sampled_not_in_transaction
        assert_nil Tracer.sampled?
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

      def test_in_transaction
        NewRelic::Agent::Tracer.in_transaction(name: 'test', category: :other) do
          # No-op
        end

        assert_metrics_recorded(['test'])
      end

      def test_in_transaction_with_early_failure
        yielded = false
        NewRelic::Agent::Transaction.any_instance.stubs(:start).raises("Boom")
        NewRelic::Agent::Tracer.in_transaction(name: 'test', category: :other) do
          yielded = true
        end

        assert yielded

        NewRelic::Agent::Tracer.clear_state
      end

      def test_in_transaction_with_late_failure
        yielded = false
        NewRelic::Agent::Transaction.any_instance.stubs(:commit!).raises("Boom")
        NewRelic::Agent::Tracer.in_transaction(name: 'test', category: :other) do
          yielded = true
        end

        assert yielded
        refute_metrics_recorded(['test'])
      end

      def test_in_transaction_notices_errors
        assert_raises RuntimeError do
          NewRelic::Agent::Tracer.in_transaction(name: 'test', category: :other) do
            raise "O_o"
          end
        end

        assert_metrics_recorded(["Errors/all"])
      end

      def test_start_transaction_without_one_already_existing
        assert_nil Tracer.current_transaction

        txn = Tracer.start_transaction(name: "Controller/Blogs/index",
                                       category: :controller)

        assert_equal txn, Tracer.current_transaction

        txn.finish
        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_returns_current_if_already_in_progress
        in_transaction do |txn1|
          refute_nil Tracer.current_transaction

          txn2 = Tracer.start_transaction(name: "Controller/Blogs/index",
                                         category: :controller)

          assert_equal txn2, txn1
          assert_equal txn2, Tracer.current_transaction
        end
      end

      def test_start_transaction_or_segment_without_active_txn
        assert_nil Tracer.current_transaction

        finishable = Tracer.start_transaction_or_segment(
          name: "Controller/Blogs/index",
          category: :controller
        )

        assert_equal finishable, Tracer.current_transaction

        finishable.finish
        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_or_segment_with_active_txn
        in_transaction do |txn|
          finishable = Tracer.start_transaction_or_segment(
            name: "Middleware/Rack/MyMiddleWare/call",
            category: :middleware
          )

          #todo: Implement current_segment on Tracer
          assert_equal finishable, Tracer.current_transaction.current_segment

          finishable.finish
          refute_nil Tracer.current_transaction
        end

        assert_nil Tracer.current_transaction
      end

      def test_start_transaction_or_segment_mulitple_calls
        f1 = Tracer.start_transaction_or_segment(
          name: "Controller/Rack/Test::App/call",
          category: :rack
        )

        f2 = Tracer.start_transaction_or_segment(
          name: "Middleware/Rack/MyMiddleware/call",
          category: :middleware
        )

        f3 = Tracer.start_transaction_or_segment(
          name: "Controller/blogs/index",
          category: :controller
        )

        f4 = Tracer.start_segment(name: "Custom/MyClass/my_meth")

        f4.finish
        f3.finish
        f2.finish
        f1.finish

        assert_metrics_recorded [
          ["Nested/Controller/Rack/Test::App/call", "Controller/blogs/index"],
          ["Middleware/Rack/MyMiddleware/call",     "Controller/blogs/index"],
          ["Nested/Controller/blogs/index",         "Controller/blogs/index"],
          ["Custom/MyClass/my_meth",                "Controller/blogs/index"],
          "Controller/blogs/index",
          "Nested/Controller/Rack/Test::App/call",
          "Middleware/Rack/MyMiddleware/call",
          "Nested/Controller/blogs/index",
          "Custom/MyClass/my_meth"
        ]
      end

      def test_start_transaction_or_segment_mulitple_calls_with_partial_name
        f1 = Tracer.start_transaction_or_segment(
          partial_name: "Test::App/call",
          category: :rack
        )

        f2 = Tracer.start_transaction_or_segment(
          partial_name: "MyMiddleware/call",
          category: :middleware
        )

        f3 = Tracer.start_transaction_or_segment(
          partial_name: "blogs/index",
          category: :controller
        )

        f3.finish
        f2.finish
        f1.finish

        assert_metrics_recorded [
          ["Nested/Controller/Rack/Test::App/call", "Controller/blogs/index"],
          ["Middleware/Rack/MyMiddleware/call",     "Controller/blogs/index"],
          ["Nested/Controller/blogs/index",         "Controller/blogs/index"],
          "Controller/blogs/index",
          "Nested/Controller/Rack/Test::App/call",
          "Middleware/Rack/MyMiddleware/call",
          "Nested/Controller/blogs/index",
        ]
      end

      def test_start_transaction_with_partial_name
        txn = Tracer.start_transaction(
          partial_name: "Test::App/call",
          category: :rack
        )

        txn.finish

        assert_metrics_recorded ["Controller/Rack/Test::App/call"]
      end

      def test_current_segment_with_transaction
        assert_nil Tracer.current_segment

        txn = Tracer.start_transaction(name: "Controller/blogs/index", category: :controller)
        assert_equal txn.initial_segment, Tracer.current_segment

        segment = Tracer.start_segment(name: "Custom/MyClass/myoperation")
        assert_equal segment, Tracer.current_segment

        txn.finish

        assert_nil Tracer.current_segment
      end

      def test_current_segment_without_transaction
        assert_nil Tracer.current_segment
        Tracer.start_segment(name: "Custom/MyClass/myoperation")
        assert_nil Tracer.current_segment
      end

      def test_start_segment
        name = "Custom/MyClass/myoperation"
        unscoped_metrics = [
          "Custom/Segment/something/all",
          "Custom/Segment/something/allWeb"
        ]
        parent = Transaction::Segment.new("parent")
        start_time = Time.now

        in_transaction 'test' do
          segment = Tracer.start_segment(
           name: name,
           unscoped_metrics: unscoped_metrics,
           parent: parent,
           start_time: start_time
          )

          assert_equal segment, Tracer.current_segment

          segment.finish
        end
      end

      def test_start_datastore_segment
        product         = "MySQL"
        operation       = "INSERT"
        collection      = "blogs"
        host            = "localhost"
        port_path_or_id = "3306"
        database_name   = "blog_app"
        start_time      = Time.now
        parent          = Transaction::Segment.new("parent")

        in_transaction 'test' do
          segment = Tracer.start_datastore_segment(
            product: product,
            operation: operation,
            collection: collection,
            host: host,
            port_path_or_id: port_path_or_id,
            database_name: database_name,
            start_time: start_time,
            parent: parent
          )

          assert_equal segment, Tracer.current_segment

          segment.finish
        end
      end

      def test_start_external_request_segment
        library    = "Net::HTTP"
        uri        = "https://docs.newrelic.com"
        procedure  = "GET"
        start_time = Time.now
        parent     = Transaction::Segment.new("parent")

        in_transaction 'test' do
          segment = Tracer.start_external_request_segment(
            library: library,
            uri: uri,
            procedure: procedure,
            start_time: start_time,
            parent: parent
          )

          assert_equal segment, Tracer.current_segment

          segment.finish
        end
      end

      def test_accept_distributed_trace_payload_delegates_to_transaction
        payload = stub(:payload)
        in_transaction do |txn|
          txn.expects(:accept_distributed_trace_payload).with(payload)
          Tracer.accept_distributed_trace_payload(payload)
        end
      end

      def test_create_distributed_trace_payload_delegates_to_transaction
        in_transaction do |txn|
          txn.distributed_tracer.expects(:create_distributed_trace_payload)
          Tracer.create_distributed_trace_payload
        end
      end
    end
  end
end
