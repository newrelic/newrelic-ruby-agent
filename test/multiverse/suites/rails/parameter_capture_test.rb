# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'

class ParameterCaptureController < ApplicationController
  def transaction
    render :text => 'hi!'
  end

  def error
    raise 'wut'
  end

  # For Rails 3+, this is configured globally in the config block for the app
  if Rails::VERSION::MAJOR == 2
    filter_parameter_logging(:secret)
  end
end

class ParameterCaptureTest < RailsMultiverseTest
  def setup
    NewRelic::Agent.drop_buffered_data
  end

  def test_no_params_captured_on_errors_when_disabled
    with_config(:capture_params => false) do
      get '/parameter_capture/error?other=1234&secret=4567'
    end
    assert_nil last_traced_error_request_params
  end

  def test_no_params_captured_on_tts_when_disabled
    with_config(:capture_params => false) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end
    assert_equal({}, last_transaction_trace_request_params)
  end

  def test_filters_parameters_on_traced_errors
    with_config(:capture_params => true) do
      get '/parameter_capture/error?other=1234&secret=4567'
    end

    captured_params = last_traced_error_request_params
    assert_equal('[FILTERED]', captured_params['secret'])
    assert_equal('1234',       captured_params['other'])
  end

  def test_filters_parameters_on_transaction_traces
    with_config(:capture_params => true) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end

    captured_params = last_transaction_trace_request_params
    assert_equal('[FILTERED]', captured_params['secret'])
    assert_equal('1234',       captured_params['other'])
  end


  def test_no_params_captured_when_bails_before_rails
    with_config(:capture_params => false) do
      get '/middleware_error/before?other=1234&secret=4567'
    end
    assert_nil last_traced_error_request_params
    assert_equal({}, last_transaction_trace_request_params)
  end

  if Rails::VERSION::MAJOR.to_i >= 3
    # NewRelic::Rack::ErrorCollector grabs things out of the request so
    # we get the actual params even if we never got to a controller
    def test_sees_error_params_even_when_bailing_before_rails_if_enabled
      with_config(:capture_params => true) do
        get '/middleware_error/before?other=1234&secret=4567'
      end

      captured_params = last_traced_error_request_params
      assert_equal('[FILTERED]', captured_params['secret'])
      assert_equal('1234',       captured_params['other'])
    end
  else
    def test_sees_error_params_even_when_bailing_before_rails_if_enabled
      with_config(:capture_params => true) do
        get '/middleware_error/before?other=1234&secret=4567'
      end
      assert_nil last_traced_error_request_params
    end
  end

  def test_no_params_captured_on_tt_when_bails_before_rails_even_when_enabled
    with_config(:capture_params => true) do
      get '/middleware_error/before?other=1234&secret=4567'
    end

    assert_equal({}, last_transaction_trace_request_params)
  end

  def last_traced_error
    NewRelic::Agent.agent.error_collector.errors.last
  end

  def last_traced_error_request_params
    last_traced_error.params[:request_params]
  end

  def last_transaction_trace
    NewRelic::Agent.agent.transaction_sampler.last_sample
  end

  def last_transaction_trace_request_params
    last_transaction_trace.params[:request_params]
  end

end
