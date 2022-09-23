# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../.github/workflows/scripts/slack_notifications/slack_notifier'

class SlackNotifications < Minitest::Test
  def test_send_slack_message_zero_args
    SlackNotifier.stub(:sleep, nil) do
      assert_raises(ArgumentError) { SlackNotifier.send_slack_message() }
    end
  end

  def test_send_slack_message_too_many_args
    SlackNotifier.stub(:sleep, nil) do
      assert_raises(ArgumentError) {
        SlackNotifier.send_slack_message("I am a notification message!", "But I'm one too many")
      }
    end
  end

  def test_send_slack_message
    SlackNotifier.stub(:sleep, nil) do
      HTTParty.stub(:post, nil) do
        assert_nil SlackNotifier.send_slack_message("I am a notification message!")
      end
    end
  end
end
