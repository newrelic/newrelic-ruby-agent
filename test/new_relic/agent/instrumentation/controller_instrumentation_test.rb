# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))

module NewRelic::Agent::Instrumentation
  class ControllerInstrumentationTest < Minitest::Test

    class TestObject
      include ControllerInstrumentation

      def public_transaction(*args); end

      protected
      def protected_transaction(*args); end

      private
      def private_transaction(*args); end

      add_transaction_tracer :public_transaction
      add_transaction_tracer :protected_transaction
      add_transaction_tracer :private_transaction
    end

    class TestParent
      include ControllerInstrumentation

      newrelic_ignore_apdex

      def foo(*args); end

      add_transaction_tracer :foo
    end

    class TestChild < TestParent
      def bar(*args); end

      add_transaction_tracer :bar
    end

    def setup
      NewRelic::Agent.drop_buffered_data
      @object = TestObject.new
      @dummy_headers = { :request => 'headers' }
      @txn_namer = ControllerInstrumentation::TransactionNamer
    end

    def teardown
      NewRelic::Agent.instance.stats_engine.clear_stats
    end

    def test_apdex_recorded
      @object.public_transaction
      assert_metrics_recorded("Apdex")
    end

    def test_apdex_ignored
      @object.stubs(:ignore_apdex?).returns(true)
      @object.public_transaction
      assert_metrics_not_recorded("Apdex")
    end

    def test_apdex_ignored_if_ignored_in_parent_class
      obj = TestChild.new

      obj.foo
      obj.bar

      assert_metrics_not_recorded("Apdex")
    end

    def test_children_respect_parental_ignore_rules_with_only
      parent = Class.new do
        include ControllerInstrumentation

        newrelic_ignore(:only => :foo)

        def foo(*args); end
        def foo2(*args); end
      end

      child = Class.new(parent) do
        newrelic_ignore(:only => :bar)

        def bar(*args); end
        def bar2(*args); end
      end

      key = ControllerInstrumentation::NR_DO_NOT_TRACE_KEY

      assert IgnoreActions.is_filtered?(key, child, :foo )
      assert IgnoreActions.is_filtered?(key, child, :bar )
      refute IgnoreActions.is_filtered?(key, child, :foo2)
      refute IgnoreActions.is_filtered?(key, child, :bar2)
    end

    def test_children_respect_parental_ignore_rules_with_except
      parent = Class.new do
        include ControllerInstrumentation

        newrelic_ignore(:except => :foo)

        def foo(*args); end
        def foo2(*args); end
      end

      child = Class.new(parent) do
        newrelic_ignore(:except => :bar)

        def bar(*args); end
        def bar2(*args); end
      end

      key = ControllerInstrumentation::NR_DO_NOT_TRACE_KEY

      assert IgnoreActions.is_filtered?(key, child, :foo )
      assert IgnoreActions.is_filtered?(key, child, :bar )
      assert IgnoreActions.is_filtered?(key, child, :foo2)
      assert IgnoreActions.is_filtered?(key, child, :bar2)
    end

    def test_children_respect_parental_ignore_rules_with_except_and_only
      parent = Class.new do
        include ControllerInstrumentation

        newrelic_ignore(:only => :foo)

        def foo(*args); end
        def foo2(*args); end
      end

      child = Class.new(parent) do
        newrelic_ignore(:except => :foo)

        def bar(*args); end
      end

      key = ControllerInstrumentation::NR_DO_NOT_TRACE_KEY

      assert IgnoreActions.is_filtered?(key, child, :foo )
      assert IgnoreActions.is_filtered?(key, child, :bar )
      assert IgnoreActions.is_filtered?(key, child, :foo2)
    end

    def test_transaction_name_calls_newrelic_metric_path
      @object.stubs(:newrelic_metric_path).returns('some/wacky/path')
      assert_equal('Controller/some/wacky/path', @txn_namer.txn_name(nil, @object, :controller))
    end

    def test_transaction_name_applies_category_and_path
      assert_equal('Controller/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       :controller,
                                       :path => 'metric/path'))
      assert_equal('OtherTransaction/Background/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       :task,
                                       :path => 'metric/path'))
      assert_equal('Controller/Rack/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       :rack,
                                       :path => 'metric/path'))
      assert_equal('Controller/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       :uri,
                                       :path => 'metric/path'))
      assert_equal('Controller/Sinatra/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       :sinatra,
                                       :path => 'metric/path'))
      assert_equal('Blarg/metric/path',
                   @txn_namer.txn_name(nil,
                                       @object,
                                       'Blarg',
                                       :path => 'metric/path'))
    end

    def test_transaction_name_uses_class_name_if_path_not_specified
      assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject',
                   @txn_namer.txn_name(nil, @object, :controller))
    end

    def test_transaction_name_applies_action_name_if_specified_and_not_path
      assert_equal('Controller/NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/action',
                     @txn_namer.txn_name(nil,
                                         @object,
                                         :controller,
                                         :name => 'action'))
    end

    def test_transaction_path_name
      result = @txn_namer.path_name(@object)
      assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject", result)
    end

    def test_transaction_path_name_with_name
      result = @txn_namer.path_name(@object, :name => "test")
      assert_equal("NewRelic::Agent::Instrumentation::ControllerInstrumentationTest::TestObject/test", result )
    end

    def test_transaction_path_name_with_overridden_class_name
      result = @txn_namer.path_name(@object, :name => "perform", :class_name => 'Resque')
      assert_equal("Resque/perform", result)
    end

    def test_add_transaction_tracer_should_not_double_instrument
      TestObject.expects(:alias_method).never
      TestObject.class_eval do
        add_transaction_tracer :public_transaction
        add_transaction_tracer :protected_transaction
        add_transaction_tracer :private_transaction
      end
      TestObject.new
    end

    def test_add_transaction_tracer_defines_with_method
      assert TestObject.method_defined? :public_transaction_with_newrelic_transaction_trace
    end

    def test_add_transaction_tracer_defines_without_method
      assert TestObject.method_defined? :public_transaction_without_newrelic_transaction_trace
    end

    def test_parse_punctuation
      ['?', '!', '='].each do |punctuation_mark|
        result = TestObject.parse_punctuation("foo#{punctuation_mark}")
        assert_equal ['foo', punctuation_mark], result
      end
    end

    def test_argument_list
      options = {:foo => :bar, :params => '{ :account_name => args[0].name }', :far => 7}
      result = TestObject.generate_argument_list(options)
      expected = [":far => \"7\"", ":foo => :bar", ":params => { :account_name => args[0].name }"]
      assert_equal expected.sort, result.sort
    end

    def test_build_method_names
      result = TestObject.build_method_names('foo', '?')
      expected = ["foo_with_newrelic_transaction_trace?", "foo_without_newrelic_transaction_trace?"]
      assert_equal expected, result
    end

    def test_already_added_transaction_tracer_returns_true_if_with_method_defined
      with_method_name = 'public_transaction_with_newrelic_transaction_trace'
      assert TestObject.already_added_transaction_tracer?(TestObject, with_method_name)
    end

    # ControllerInstrumentation historically was used to instrument Rails 2
    # controllers, and in this case is called without a block. In that case, and
    # that case *only*, we want to try to call params on the host object to
    # extract request params.
    #
    # In the more modern usage where it's called with a block we do *not* want to
    # call params on the host object. This is important because doing so could
    # actually crash in some cases.
    def test_should_not_call_params_on_host_if_called_with_block
      host_class = Class.new do
        include ControllerInstrumentation

        # It's a more realistic test if the host class actually responds to params
        def params
          raise 'no!'
        end

        def doit
          perform_action_with_newrelic_trace do
            # nothing
          end
        end
      end

      host = host_class.new
      host.expects(:params).never
      host.doit
    end

    def test_should_not_call_params_on_host_if_no_block_given_but_does_not_respond_to_params
      host_class = Class.new do
        include ControllerInstrumentation

        def doit
          perform_action_with_newrelic_trace
        end

        def perform_action_without_newrelic_trace; end
      end

      host = host_class.new
      refute host.respond_to?(:params)
      host.doit
    end

    def test_should_call_params_on_host_if_no_block_given_and_host_responds
      host_class = Class.new do
        include ControllerInstrumentation

        attr_reader :params_called

        def params
          @params_called = true
          {}
        end

        def doit
          perform_action_with_newrelic_trace
        end

        def perform_action_without_newrelic_trace; end
      end

      host = host_class.new
      host.doit
      assert host.params_called
    end

    class UserError < StandardError
    end

    def test_failure_during_starting_shouldnt_override_error_raised
      host_class = Class.new do
        include ControllerInstrumentation

        def doit
          perform_action_with_newrelic_trace do
            raise UserError.new
          end
        end
      end

      NewRelic::Agent::Transaction.stubs(:start).returns(nil)

      host = host_class.new
      assert_raises(UserError) do
        host.doit
      end
    end

    def test_should_not_set_request
      clazz = Class.new do
        include ControllerInstrumentation

        def doit
          perform_action_with_newrelic_trace do
            NewRelic::Agent::TransactionState.tl_get.current_transaction.request
          end
        end
      end

      request = clazz.new.doit
      assert_nil request
    end
  end
end
