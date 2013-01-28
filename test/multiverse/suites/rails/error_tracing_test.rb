# https://newrelic.atlassian.net/browse/RUBY-747

require 'rails/test_help'
require 'fake_collector'

class ErrorController < ApplicationController
  include Rails.application.routes.url_helpers
  newrelic_ignore :only => :ignored_action

  def controller_error
    raise 'this is an uncaught controller error'
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

  def noticed_error
    newrelic_notice_error(RuntimeError.new('this error should be noticed'))
    render :text => "Shoulda noticed an error"
  end
end

class IgnoredError < StandardError; end
class ServerIgnoredError < StandardError; end

class ErrorsWithoutSSCTest < ActionDispatch::IntegrationTest
  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    setup_collector
    $collector.run

    NewRelic::Agent.reset_config
    NewRelic::Agent.instance_variable_set(:@agent, nil)
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
    NewRelic::Agent.manual_start

    reset_error_collector
  end

  # Let base class override this without moving where we start the agent
  def setup_collector
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666 }}]
  end

  def teardown
    NewRelic::Agent::Agent.instance.shutdown if NewRelic::Agent::Agent.instance
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
  end

  def reset_error_collector
    @error_collector = NewRelic::Agent::Agent.instance.error_collector

    # sanity checks
    assert(@error_collector.enabled?,
           'error collector should be enabled')
    assert(!NewRelic::Agent.instance.error_collector.ignore_error_filter,
           'no ignore error filter should be set')
  end


  def test_error_collector_should_be_enabled
    assert NewRelic::Agent.config[:agent_enabled]
    assert NewRelic::Agent.config[:'error_collector.enabled']
    assert @error_collector.enabled?
    assert Rails.application.config.middleware.include?(NewRelic::Rack::ErrorCollector)
  end

  def test_should_capture_error_raised_in_view
    get '/error/view_error'
    assert_error_reported_once('this is an uncaught view error')
  end

  def test_should_capture_error_raised_in_controller
    get '/error/controller_error'
    assert_error_reported_once('this is an uncaught controller error')
  end

  def test_should_capture_error_raised_in_model
    get '/error/model_error'
    assert_error_reported_once('this is an uncaught model error')
  end

  def test_should_capture_noticed_error_in_controller
    get '/error/noticed_error'
    assert_error_reported_once('this error should be noticed')
  end

  def test_should_capture_manually_noticed_error
    NewRelic::Agent.notice_error(RuntimeError.new('this is a noticed error'))
    assert_error_reported_once('this is a noticed error')
  end

  def test_should_capture_routing_error
    get '/bad_route'
    assert_error_reported_once('this is an uncaught routing error')
  end

  def test_should_capture_request_uri_and_params
    get '/bad_route?eat=static'
    assert_equal('/bad_route',
                 @error_collector.errors[0].params[:request_uri])
    assert_equal({'eat' => 'static'},
                 @error_collector.errors[0].params[:request_params])
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

 protected

  def assert_error_reported_once(message)
    assert_equal(message,
                 @error_collector.errors[0].message,
                 'This error type was not detected')
    assert_equal(1, @error_collector.errors.size,
                 'Too many of this error type was detected')
  end
end

class ErrorsWithSSCTest < ErrorsWithoutSSCTest
  def setup_collector
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
