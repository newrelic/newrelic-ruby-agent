# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-747
require './app'
require 'fake_collector'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'exceptions'))

class ErrorController < ApplicationController
  include NewRelic::TestHelpers::Exceptions

  newrelic_ignore :only => :ignored_action

  def controller_error
    raise 'this is an uncaught controller error'
  end

  def exception_error
    raise Exception.new('wobble')
  end

  def view_error
    render :inline => "<% raise 'this is an uncaught view error' %>"
  end

  def model_error
    Foo.new.raise_error
  end

  def ignored_action
    raise 'this error should not be noticed'
  end

  def ignored_error
    raise NewRelic::TestHelpers::Exceptions::IgnoredError.new('this error should not be noticed')
  end

  def server_ignored_error
    raise NewRelic::TestHelpers::Exceptions::ServerIgnoredError.new('this is a server ignored error')
  end

  def frozen_error
    e = RuntimeError.new("frozen errors make a refreshing treat on a hot summer day")
    e.freeze
    raise e
  end

  def string_noticed_error
    NewRelic::Agent.notice_error("trilobites died out millions of years ago")
    render :text => 'trilobites'
  end

  def noticed_error
    NewRelic::Agent.notice_error(RuntimeError.new('this error should be noticed'))
    render :text => "Shoulda noticed an error"
  end

  def deprecated_noticed_error
    newrelic_notice_error(RuntimeError.new('this error should be noticed'))
    render :text => "Shoulda noticed an error"
  end

  def middleware_error
    render :text => 'everything went great'
  end

  def error_with_custom_params
    NewRelic::Agent.add_custom_attributes(:texture => 'chunky')
    raise 'bad things'
  end

  if Rails::VERSION::MAJOR == 2
    filter_parameter_logging(:secret)
  end
end

class ErrorsWithoutSSCTest < RailsMultiverseTest
  extend Multiverse::Color

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    setup_collector_mocks
    @error_collector = agent.error_collector
  end

  # Let base class override this without moving where we start the agent
  def setup_collector_mocks
    $collector.stub('connect', {"agent_run_id" => 666 }, 200)
  end

  def last_error
    errors.last
  end

  if Rails::VERSION::MAJOR >= 3
    def test_error_collector_should_be_enabled
      assert NewRelic::Agent.config[:agent_enabled]
      assert NewRelic::Agent.config[:'error_collector.enabled']
      assert @error_collector.enabled?
    end

    def test_should_capture_routing_error
      get '/bad_route'
      assert_error_reported_once('this is an uncaught routing error', nil, nil)
    end

    def test_should_capture_errors_raised_in_middleware_before_call
      get '/error/middleware_error/before'
      assert_error_reported_once('middleware error', nil, nil)
    end

    def test_should_capture_errors_raised_in_middleware_after_call
      get '/error/middleware_error/after'
      assert_error_reported_once('middleware error', nil, nil)
    end

    def test_should_capture_request_uri_and_params
      get '/error/controller_error?eat=static'
      assert_equal('/error/controller_error', attributes_for_single_error_posted("request_uri"))

      expected_params = {
        'request.parameters.eat' => 'static',
        'httpResponseCode' => '500'
      }

      attributes = agent_attributes_for_single_error_posted
      expected_params.each do |key, value|
        assert_equal value, attributes[key]
      end
    end
  end

  def test_should_capture_error_raised_in_view
    get '/error/view_error'
    assert_error_reported_once('this is an uncaught view error',
                               'Controller/error/view_error')
  end

  def test_should_capture_error_raised_in_controller
    get '/error/controller_error'
    assert_error_reported_once('this is an uncaught controller error',
                               'Controller/error/controller_error')
  end

  def test_should_capture_error_raised_in_model
    get '/error/model_error'
    assert_error_reported_once('this is an uncaught model error',
                               'Controller/error/model_error')
  end

  if Rails::VERSION::MAJOR < 5
    def test_should_capture_deprecated_noticed_error_in_controller
      get '/error/deprecated_noticed_error'
      assert_error_reported_once('this error should be noticed',
                                 'Controller/error/deprecated_noticed_error')
    end
  end

  def test_should_capture_noticed_error_in_controller
    get '/error/noticed_error'
    assert_error_reported_once('this error should be noticed',
                               'Controller/error/noticed_error')
  end

  def test_should_capture_frozen_errors
    get '/error/frozen_error'
    assert_error_reported_once("frozen errors make a refreshing treat on a hot summer day",
                               "Controller/error/frozen_error")
  end

  def test_should_capture_string_noticed_errors
    get '/error/string_noticed_error'
    assert_error_reported_once("trilobites died out millions of years ago",
                               "Controller/error/string_noticed_error")
  end

  # Important choice of controllor_error, since this goes through both the
  # transaction and the rack error collector, so risks multiple counting!
  def test_should_capture_multiple_errors
    40.times do
      get '/error/controller_error'
    end

    assert_errors_reported('this is an uncaught controller error',
                           NewRelic::Agent::ErrorCollector::MAX_ERROR_QUEUE_LENGTH,
                           40, nil, 40)
  end

  def test_should_capture_manually_noticed_error
    NewRelic::Agent.notice_error(RuntimeError.new('this is a noticed error'))
    assert_error_reported_once('this is a noticed error', nil, nil)
  end

  def test_should_apply_parameter_filtering
    get '/error/controller_error?secret=shouldnotbecaptured&other=whatever'
    attributes = agent_attributes_for_single_error_posted
    assert_equal('[FILTERED]', attributes['request.parameters.secret'])
    assert_equal('whatever', attributes['request.parameters.other'])
  end

  def test_should_apply_parameter_filtering_for_non_standard_errors
    get '/error/exception_error?secret=shouldnotbecaptured&other=whatever'
    attributes = agent_attributes_for_single_error_posted
    assert_equal('[FILTERED]', attributes['request.parameters.secret'])
    assert_equal('whatever', attributes['request.parameters.other'])
  end

  def test_should_not_notice_errors_from_ignored_action
    get '/error/ignored_action'
    assert(errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_not_notice_ignored_error_classes
    get '/error/ignored_error'
    assert(errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_not_fail_apdex_for_ignored_error_class_noticed
    get '/error/ignored_error'
    assert_metrics_recorded({
      'Apdex'                     => { :apdex_f => 0 },
      'Apdex/error/ignored_error' => { :apdex_f => 0 }
    })
  end

  def test_should_not_notice_filtered_errors
    filter = Proc.new do |error|
      !error.kind_of?(RuntimeError)
    end

    with_ignore_error_filter(filter) do
      get '/error/controller_error'
    end

    assert(errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_notice_server_ignored_error_if_no_server_side_config
    get '/error/server_ignored_error'
    assert_error_reported_once('this is a server ignored error')
  end

  def test_captured_errors_should_include_custom_params
    with_config(:'error_collector.attributes.enabled' => true) do
      get '/error/error_with_custom_params'
      assert_error_reported_once('bad things')

      attributes = user_attributes_for_single_error_posted
      assert_equal({'texture' => 'chunky'}, attributes)
    end
  end

  def test_captured_errors_should_include_custom_params_with_legacy_setting
    with_config(:'error_collector.capture_attributes' => true) do
      get '/error/error_with_custom_params'
      assert_error_reported_once('bad things')

      attributes = user_attributes_for_single_error_posted
      assert_equal({'texture' => 'chunky'}, attributes)
    end
  end

  def test_captured_errors_should_not_include_custom_params_if_config_says_no
    with_config(:'error_collector.attributes.enabled' => false) do
      get '/error/error_with_custom_params'
      assert_error_reported_once('bad things')

      attributes = user_attributes_for_single_error_posted
      assert_empty attributes
    end
  end

  def test_captured_errors_should_not_include_custom_params_if_legacy_setting_says_no
    with_config(:'error_collector.capture_attributes' => false) do
      get '/error/error_with_custom_params'
      assert_error_reported_once('bad things')

      attributes = user_attributes_for_single_error_posted
      assert_empty attributes
    end
  end

  protected

  def errors
    @error_collector.error_trace_aggregator.instance_variable_get :@errors
  end

  def errors_with_message(message)
    errors.select{|error| error.message == message}
  end

  def assert_errors_reported(message, queued_count, total_count=queued_count, txn_name=nil, apdex_f=1)
    expected = { :call_count => total_count }
    assert_metrics_recorded("Errors/all" => expected)
    assert_metrics_recorded("Errors/#{txn_name}" => expected) if txn_name

    unless apdex_f.nil?
      assert_metrics_recorded("Apdex" => { :apdex_f => apdex_f })
    end

    assert_equal(queued_count,
      errors_with_message(message).size,
      "Wrong number of errors with message #{message.inspect} found")
  end

  def assert_error_reported_once(message, txn_name=nil, apdex_f=1)
    assert_errors_reported(message, 1, 1, txn_name, apdex_f)
  end
end

class ErrorsWithSSCTest < ErrorsWithoutSSCTest
  def setup_collector_mocks
    $collector.stub('connect', {
      "agent_run_id" => 1,
      "agent_config" => {
        "error_collector.ignore_errors" => 'NewRelic::TestHelpers::Exceptions::IgnoredError,NewRelic::TestHelpers::Exceptions::ServerIgnoredError',
        "error_collector.enabled" => true,
      },
      "collect_errors" => true
    }, 200)
  end

  def test_should_notice_server_ignored_error_if_no_server_side_config
    # Overrides test in base class, since doesn't apply
  end

  def test_should_ignore_server_ignored_errors
    get '/error/server_ignored_error'

    assert(errors.empty?,
           'Noticed an error that should have been ignored' + errors.join(', '))
  end

end
