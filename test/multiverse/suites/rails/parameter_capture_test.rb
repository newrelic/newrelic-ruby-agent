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
    err = last_traced_error
    assert_nil err.params[:request_params]
  end

  def test_no_params_captured_on_tts_when_disabled
    with_config(:capture_params => false) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end

    trace = last_transaction_trace
    assert_equal({}, trace.params[:request_params])
  end

  def test_filters_parameters_on_traced_errors
    with_config(:capture_params => true) do
      get '/parameter_capture/error?other=1234&secret=4567'
    end
    err = last_traced_error
    captured_params = err.params[:request_params]

    assert_equal('[FILTERED]', captured_params['secret'])
    assert_equal('1234',       captured_params['other'])
  end

  def test_filters_parameters_on_transaction_traces
    with_config(:capture_params => true) do
      get '/parameter_capture/transaction?other=1234&secret=4567'
    end
    trace = last_transaction_trace
    captured_params = trace.params[:request_params]

    assert_equal('[FILTERED]', captured_params['secret'])
    assert_equal('1234',       captured_params['other'])
  end

  def last_traced_error
    NewRelic::Agent.agent.error_collector.errors.last
  end

  def last_transaction_trace
    NewRelic::Agent.agent.transaction_sampler.last_sample
  end
end
