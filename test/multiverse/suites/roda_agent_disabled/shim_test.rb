# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'roda'

class TestRodaApp < Roda; end

class RodaAgentDisabledTestCase < Minitest::Test
  def assert_shims_defined
    # class method shim
    assert_respond_to TestRodaApp, :newrelic_ignore, 'Class method newrelic_ignore not defined'
    assert_respond_to TestRodaApp, :newrelic_ignore_apdex, 'Class method newrelic_ignore_apdex not defined'
    assert_respond_to TestRodaApp, :newrelic_ignore_enduser, 'Class method newrelic_ignore_enduser not defined'

    # instance method shims
    assert_includes(TestRodaApp.instance_methods, :perform_action_with_newrelic_trace, 'Instance method perform_action_with_newrelic_trace not defined')
  end

  # Agent disabled via config/newrelic.yml
  def test_shims_exist_when_agent_enabled_false
    assert_shims_defined
  end
end
