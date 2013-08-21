# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-747
require 'rails/test_help'
require 'fake_collector'
require 'multiverse_helpers'

class ErrorController < ApplicationController
  include Rails.application.routes.url_helpers
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
    raise IgnoredError.new('this error should not be noticed')
  end

  def server_ignored_error
    raise ServerIgnoredError.new('this is a server ignored error')
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
    newrelic_notice_error(RuntimeError.new('this error should be noticed'))
    render :text => "Shoulda noticed an error"
  end

  def middleware_error
    render :text => 'everything went great'
  end
end

class IgnoredError < StandardError; end
class ServerIgnoredError < StandardError; end

class ErrorsWithoutSSCTest < ActionDispatch::IntegrationTest
  extend Multiverse::Color

  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    setup_collector_mocks
    @error_collector = agent.error_collector
  end

  # Let base class override this without moving where we start the agent
  def setup_collector_mocks
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666 }}]
  end

  def last_error
    @error_collector.errors.last
  end

  def test_error_collector_should_be_enabled
    assert NewRelic::Agent.config[:agent_enabled]
    assert NewRelic::Agent.config[:'error_collector.enabled']
    assert @error_collector.enabled?
    assert Rails.application.config.middleware.include?(NewRelic::Rack::ErrorCollector)
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

    assert_errors_reported('this is an uncaught controller error', 20, 40, nil, 40)
  end

  def test_should_capture_manually_noticed_error
    NewRelic::Agent.notice_error(RuntimeError.new('this is a noticed error'))
    assert_error_reported_once('this is a noticed error', nil, nil)
  end

  def test_should_capture_routing_error
    get '/bad_route'
    assert_error_reported_once('this is an uncaught routing error', nil, nil)
  end

  def test_should_apply_parameter_filtering
    get '/error/controller_error?secret=shouldnotbecaptured&other=whatever'
    params = last_error.params[:request_params]
    assert_equal('[FILTERED]', params['secret'])
    assert_equal('whatever', params['other'])
  end

  def test_should_apply_parameter_filtering_for_errors_captured_by_rack_error_collector
    get '/error/exception_error?secret=shouldnotbecaptured&other=whatever'
    params = last_error.params[:request_params]
    assert_equal('[FILTERED]', params['secret'])
    assert_equal('whatever', params['other'])
  end

  def test_should_capture_request_uri_and_params
    get '/bad_route?eat=static'
    assert_equal('/bad_route', last_error.params[:request_uri])
    assert_equal({'eat' => 'static'}, last_error.params[:request_params])
  end

  def test_should_not_notice_errors_from_ignored_action
    get '/error/ignored_action'
    assert(@error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_not_notice_ignored_error_classes
    get '/error/ignored_error'
    assert(@error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_not_notice_filtered_errors
    NewRelic::Agent.instance.error_collector.ignore_error_filter do |error|
      !error.kind_of?(RuntimeError)
    end

    get 'test/controller_error'
    assert(NewRelic::Agent.instance.error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_notice_server_ignored_error_if_no_server_side_config
    get '/error/server_ignored_error'
    assert_error_reported_once('this is a server ignored error')
  end

  def test_should_capture_errors_raised_in_middleware_before_call
    get '/error/middleware_error/before'
    assert_error_reported_once('middleware error', nil, nil)
  end

  def test_should_capture_errors_raised_in_middleware_after_call
    get '/error/middleware_error/after'
    assert_error_reported_once('middleware error', nil, nil)
  end

 protected

  def assert_errors_reported(message, queued_count, total_count=queued_count, txn_name=nil, apdex_f=1)
    expected = { :call_count => total_count }
    assert_metrics_recorded("Errors/all" => expected)
    assert_metrics_recorded("Errors/#{txn_name}" => expected) if txn_name

    unless apdex_f.nil?
      assert_metrics_recorded("Apdex" => { :apdex_f => apdex_f })
    end

    assert_equal(queued_count,
      @error_collector.errors.select{|error| error.message == message}.size,
      "Wrong number of errors with message #{message.inspect} found")
  end

  def assert_error_reported_once(message, txn_name=nil, apdex_f=1)
    assert_errors_reported(message, 1, 1, txn_name, apdex_f)
  end
end

class ErrorsWithSSCTest < ErrorsWithoutSSCTest
  def setup_collector_mocks
    $collector.mock['connect'] = [200, {'return_value' => {
      "listen_to_server_config" => true,
      "agent_run_id" => 1,
      "error_collector.ignore_errors" => 'IgnoredError,ServerIgnoredError',
      "error_collector.enabled" => true,
      "error_collector.capture_source" => true,
      "collect_errors" => true
    }}]
  end

  def test_should_notice_server_ignored_error_if_no_server_side_config
    # Overrides test in base class, since doesn't apply
  end

  def test_should_ignore_server_ignored_errors
    get '/error/server_ignored_error'
    assert(@error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

end
