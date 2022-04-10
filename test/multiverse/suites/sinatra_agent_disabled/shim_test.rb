# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'sinatra'

class MiddlewareApp < Sinatra::Base
  get '/middle' do
    "From the middlewarez"
  end
end

class SinatraAgentDisabledTestCase < Minitest::Test
  def teardown
    NewRelic::Agent.instance.shutdown
    NewRelic::Agent.drop_buffered_data
  end

  def assert_shims_defined
    # class method shim
    assert MiddlewareApp.respond_to?(:newrelic_ignore), "Class method newrelic_ignore not defined"
    assert MiddlewareApp.respond_to?(:newrelic_ignore_apdex), "Class method newrelic_ignore_apdex not defined"
    assert MiddlewareApp.respond_to?(:newrelic_ignore_enduser), "Class method newrelic_ignore_enduser not defined"

    # instance method shims
    assert MiddlewareApp.instance_methods.include?(:new_relic_trace_controller_action), "Instance method new_relic_trace_controller_action not defined"
    assert MiddlewareApp.instance_methods.include?(:perform_action_with_newrelic_trace), "Instance method perform_action_with_newrelic_trace not defined"
  end

  def test_shims_exist_when_agent_enabled_false
    NewRelic::Agent.manual_start(:agent_enabled => false)
    assert_shims_defined
  end
end
