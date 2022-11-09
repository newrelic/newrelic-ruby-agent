# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NewRelic::Agent::Instrumentation::ActionControllerSubscriberTest < Minitest::Test
  class TestController
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def self.controller_path
      'test'
    end

    def action_name
      'test'
    end

    # these need to exist for code level metrics to find them
    def index; end
    def child; end
    def ignored_action; end
    def ignored_apdex; end
    def ignored_enduser; end

    newrelic_ignore :only => :ignored_action
    newrelic_ignore_apdex :only => :ignored_apdex
    newrelic_ignore_enduser :only => :ignored_enduser
  end

  def setup
    nr_freeze_process_time
    @subscriber = NewRelic::Agent::Instrumentation::ActionControllerSubscriber.new
    NewRelic::Agent.drop_buffered_data
    @request = ActionDispatch::Request.new({'REQUEST_METHOD' => 'POST'})
    @headers = ActionDispatch::Http::Headers.new(@request)
    @entry_payload = {
      :controller => TestController.to_s,
      :action => 'index',
      :format => :html,
      :method => 'GET',
      :path => '/tests',
      :headers => @headers,
      :params => {:controller => 'test_controller', :action => 'index'}
    }

    @exit_payload = @entry_payload.merge(:status => 200, :view_runtime => 5.0,
      :db_runtime => 0.5)
    @stats_engine = NewRelic::Agent.instance.stats_engine
    @stats_engine.clear_stats
    NewRelic::Agent.manual_start
    NewRelic::Agent::Tracer.clear_state
  end

  def teardown
    NewRelic::Agent.shutdown
    @stats_engine.clear_stats
  end

  def test_record_controller_metrics
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_process_time(2)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = {:call_count => 1, :total_call_time => 2.0}

    assert_metrics_recorded(
      'Controller/test/index' => expected_values,
      'HttpDispatcher' => expected_values
    )
  end

  def test_record_apdex_metrics
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_process_time(1.5)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = {:apdex_f => 0, :apdex_t => 1, :apdex_s => 0}

    assert_metrics_recorded(
      'Apdex/test/index' => expected_values,
      'Apdex' => expected_values
    )
  end

  def test_record_apdex_metrics_with_error
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_process_time(1.5)

    error = StandardError.new("boo")
    @exit_payload[:exception] = error
    NewRelic::Agent.notice_error(error)

    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    expected_values = {:apdex_f => 1, :apdex_t => 0, :apdex_s => 0}

    assert_metrics_recorded(
      'Apdex/test/index' => expected_values,
      'Apdex' => expected_values
    )
  end

  def test_records_scoped_metrics_for_evented_child_txn
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.start('process_action.action_controller', :id, @entry_payload \
                        .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload \
                         .merge(:action => 'child', :path => '/child'))
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_recorded(
      ['Nested/Controller/test/child', 'Controller/test/child'] => {:call_count => 1}
    )
  end

  def test_records_scoped_metrics_for_traced_child_txn
    controller = TestController.new
    controller.perform_action_with_newrelic_trace(:category => :controller,
      :name => 'index',
      :class_name => 'test') do
      @subscriber.start('process_action.action_controller', :id, @entry_payload \
                          .merge(:action => 'child', :path => '/child'))
      @subscriber.finish('process_action.action_controller', :id, @exit_payload \
                           .merge(:action => 'child', :path => '/child'))
    end

    assert_metrics_recorded(
      ['Nested/Controller/test/child', 'Controller/test/child'] => {:call_count => 1}
    )
  end

  def test_format_metric_name
    metric_name = @subscriber.format_metric_name('index', TestController)

    assert_equal 'Controller/test/index', metric_name
  end

  def test_sets_default_transaction_name_on_start
    @subscriber.start('process_action.action_controller', :id, @entry_payload)

    assert_equal 'Controller/test/index', NewRelic::Agent::Transaction.tl_current.best_name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_default_transaction_keeps_name_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.tl_current
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)

    assert_equal 'Controller/test/index', txn.best_name
  end

  def test_sets_transaction_name
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.set_transaction_name('something/else')

    assert_equal 'Controller/something/else', NewRelic::Agent::Transaction.tl_current.best_name
  ensure
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)
  end

  def test_sets_transaction_name_holds_through_stop
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.tl_current
    NewRelic::Agent.set_transaction_name('something/else')
    @subscriber.finish('process_action.action_controller', :id, @entry_payload)

    assert_equal 'Controller/something/else', txn.best_name
  end

  def test_record_nothing_for_ignored_action
    @entry_payload[:action] = 'ignored_action'
    @exit_payload[:action] = 'ignored_action'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_not_recorded([
      'Controller/test/ignored_action',
      'Apdex/test/ignored_action',
      'Apdex',
      'HttpDispatcher'
    ])
  end

  def test_record_no_apdex_metric_for_ignored_apdex_action
    @entry_payload[:action] = 'ignored_apdex'
    @exit_payload[:action] = 'ignored_apdex'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_recorded(['Controller/test/ignored_apdex', 'HttpDispatcher'])
    assert_metrics_not_recorded(['Apdex', 'Apdex/test/ignored_apdex'])
  end

  def test_ignore_end_user
    @entry_payload[:action] = 'ignored_enduser'
    @exit_payload[:action] = 'ignored_enduser'
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    txn = NewRelic::Agent::Transaction.tl_current
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_predicate txn, :ignore_enduser?
  end

  def test_record_busy_time
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    advance_process_time(1)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    NewRelic::Agent::TransactionTimeAggregator.harvest!

    assert_metrics_recorded('Instance/Busy' => {:call_count => 1, :total_call_time => 1.0})
  end

  def test_creates_transaction
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    last_sample = last_transaction_trace

    assert_equal('Controller/test/index',
      last_sample.transaction_name)
    assert_equal('Controller/test/index',
      last_sample.root_node.children[0].metric_name)
  end

  def test_applies_txn_name_rules
    rule_specs = [{'match_expression' => 'test', 'replacement' => 'taste'}]

    with_transaction_renaming_rules(rule_specs) do
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    assert_metrics_recorded(['Controller/taste/index'])
    assert_metrics_not_recorded(['Controller/test/index'])
  end

  def test_record_queue_time_metrics
    app = lambda do |env|
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      advance_process_time(2)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    t0 = Process.clock_gettime(Process::CLOCK_REALTIME)
    env = {'HTTP_X_REQUEST_START' => (t0 - 5).to_s}
    ::NewRelic::Rack::AgentHooks.new(app).call(env)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count => 1,
        :total_call_time => 5.0
      }
    )
  end

  def test_dont_record_queue_time_if_no_header
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    assert_metrics_not_recorded('WebFrontend/QueueTime')
  end

  def test_dont_record_queue_time_in_nested_transaction
    app = lambda do |env|
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    t0 = Process.clock_gettime(Process::CLOCK_REALTIME)
    env = {'HTTP_X_REQUEST_START' => (t0 - 5).to_s}
    ::NewRelic::Rack::AgentHooks.new(app).call(env)

    assert_metrics_recorded(
      'WebFrontend/QueueTime' => {
        :call_count => 1,
        :total_call_time => 5.0
      }
    )
  end

  def test_records_request_params_in_txn
    with_config(:capture_params => true) do
      @entry_payload[:params]['number'] = '666'
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    sample = last_transaction_trace

    assert_equal('666', attributes_for(sample, :agent)['request.parameters.number'])
  end

  def test_records_filtered_request_params_in_txn
    @request.env["action_dispatch.parameter_filter"] = [:password]
    with_config(:capture_params => true) do
      @entry_payload[:params]['password'] = 'secret'
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, @exit_payload)
    end

    sample = last_transaction_trace

    assert_equal('[FILTERED]', attributes_for(sample, :agent)['request.parameters.password'])
  end

  def test_records_custom_parameters_in_txn
    @subscriber.start('process_action.action_controller', :id, @entry_payload)
    NewRelic::Agent.add_custom_attributes('number' => '666')
    @subscriber.finish('process_action.action_controller', :id, @exit_payload)

    sample = last_transaction_trace

    assert_equal('666', attributes_for(sample, :custom)['number'])
  end

  def test_records_span_level_error
    exception_class = StandardError
    exception_msg = "Natural 1"
    exception = exception_class.new(msg = exception_msg)
    # :exception_object was added in Rails 5 and above
    params = {:exception_object => exception, :exception => [exception_class.name, exception_msg]}

    txn = nil

    in_transaction do |test_txn|
      txn = test_txn
      @entry_payload[:params]['password'] = 'secret'
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      @subscriber.finish('process_action.action_controller', :id, params)
    end

    assert_segment_noticed_error txn, /controller/i, exception_class.name, /Natural 1/i
  end

  def test_records_code_level_metrics
    with_config(:'code_level_metrics.enabled' => true) do
      @subscriber.start('process_action.action_controller', :id, @entry_payload)
      txn = NewRelic::Agent::Transaction.tl_current
      @subscriber.finish('process_action.action_controller', :id, @entry_payload)
      attributes = txn.segments.first.code_attributes

      assert_equal __FILE__, attributes['code.filepath']
      assert_equal 'index', attributes['code.function']
      assert_equal TestController.instance_method(:index).source_location.last, attributes['code.lineno']
      assert_equal "NewRelic::Agent::Instrumentation::ActionControllerSubscriberTest::TestController",
        attributes['code.namespace']
    end
  end
end
