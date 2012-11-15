# https://newrelic.atlassian.net/browse/RUBY-747

ENV['NEW_RELIC_DISPATCHER'] = 'test'

require 'action_controller/railtie'
require 'rails/test_unit/railtie'
require 'rails/test_help'
require 'test/unit'
require 'new_relic/rack/error_collector'
require 'new_relic/fake_service'


# BEGIN RAILS APP

class MyApp < Rails::Application
  # We need a secret token for session, cookies, etc.
  config.active_support.deprecation = :log
  config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
end
MyApp.initialize!

MyApp.routes.draw do
  get('/bad_route' => 'Test#controller_error',
      :constraints => lambda do |_|
        raise ActionController::RoutingError.new('this is an uncaught routing error')
      end)
  match '/:controller(/:action(/:id))'
end

class ApplicationController < ActionController::Base; end

# a basic active model compliant model we can render
class Foo
  extend ActiveModel::Naming
  def to_model
    self
  end

  def valid?()      true end
  def new_record?() true end
  def destroyed?()  true end

  def raise_error
    raise 'this is an uncaught model error'
  end

  def errors
    obj = Object.new
    def obj.[](key)         [] end
    def obj.full_messages() [] end
    obj
  end
end

class TestController < ApplicationController
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
# END RAILS APP

class IgnoredError < StandardError; end
class ServerIgnoredError < StandardError; end

class TestControllerTest < ActionDispatch::IntegrationTest
  def setup
    NewRelic::Agent::Agent.instance_variable_set(:@instance, NewRelic::Agent::Agent.new)

    @service = NewRelic::FakeService.new
    NewRelic::Agent::Agent.instance.service = @service

    NewRelic::Agent.manual_start
  end

  def teardown
    NewRelic::Agent::Agent.instance.shutdown if NewRelic::Agent::Agent.instance
  end
end

class ErrorsWithoutSSCTest < TestControllerTest
  def setup
    super
    reset_error_collector
  end

  def reset_error_collector
    @error_collector = NewRelic::Agent.instance.error_collector
    NewRelic::Agent.instance.error_collector \
      .instance_variable_set(:@ignore_filter, nil)

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
    get '/test/view_error'
    assert_error_reported_once('this is an uncaught view error')
  end

  def test_should_capture_error_raised_in_controller
    get '/test/controller_error'
    assert_error_reported_once('this is an uncaught controller error')
  end

  def test_should_capture_error_raised_in_model
    get '/test/model_error'
    assert_error_reported_once('this is an uncaught model error')
  end

  def test_should_capture_noticed_error_in_controller
    get '/test/noticed_error'
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
    get '/test/ignored_action'
    assert(@error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

  def test_should_not_notice_ignored_error_classes
    get '/test/ignored_error'
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
    get '/test/server_ignored_error'
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
  def setup
    super
    @service.mock['connect'] = {
      "listen_to_server_config" => true,
      "agent_run_id" => 1,
      "error_collector.ignore_errors" => 'IgnoredError,ServerIgnoredError',
      "error_collector.enabled" => true,
      "error_collector.capture_source" => true,
      "collect_errors" => true
    }

    # Force us to apply the mocked connect values to our configuration
    NewRelic::Agent.instance.query_server_for_configuration
  end

  def test_should_notice_server_ignored_error_if_no_server_side_config
    # Overrides test in base class, since doesn't apply
  end

  def test_should_ignore_server_ignored_errors
    get '/test/server_ignored_error'
    assert(@error_collector.errors.empty?,
           'Noticed an error that should have been ignored')
  end

end
