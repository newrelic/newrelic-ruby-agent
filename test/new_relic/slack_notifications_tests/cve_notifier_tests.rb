# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../.github/workflows/scripts/slack_notifications/cve_notifier'

class CveNotifierTests < Minitest::Test
  def test_cve_message_zero_args
    assert_raises(ArgumentError) { CveNotifier.cve_message() }
  end

  def test_cve_message_one_arg
    assert_raises(ArgumentError) { CveNotifier.cve_message('allosaurus') }
  end

  def test_cve_message
    message = CveNotifier.cve_message('allosaurus', 'dinotracker.com')

    assert_equal message == '{"text":":rotating_light: allosaurus\n<dinotracker.com|More info here>"}'
    assert_kind_of String, text
  end
end
