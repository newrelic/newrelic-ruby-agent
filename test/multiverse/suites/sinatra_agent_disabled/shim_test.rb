# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'sinatra'

class MiddlewareApp < Sinatra::Base
  set :host_authorization, {permitted_hosts: []}
  get '/middle' do
    'From the middlewarez'
  end
end

class SinatraAgentDisabledTestCase < Minitest::Test
  def teardown
    NewRelic::Agent.instance.shutdown
    NewRelic::Agent.drop_buffered_data
  end

  def assert_shims_defined
    # class method shim
    assert_respond_to MiddlewareApp, :newrelic_ignore, 'Class method newrelic_ignore not defined'
    assert_respond_to MiddlewareApp, :newrelic_ignore_apdex, 'Class method newrelic_ignore_apdex not defined'
    assert_respond_to MiddlewareApp, :newrelic_ignore_enduser, 'Class method newrelic_ignore_enduser not defined'

    # instance method shims
    assert_includes(MiddlewareApp.instance_methods, :perform_action_with_newrelic_trace, 'Instance method perform_action_with_newrelic_trace not defined')
  end

  def test_shims_exist_when_agent_enabled_false
    NewRelic::Agent.manual_start(:agent_enabled => false)

    assert_shims_defined
  end
end
