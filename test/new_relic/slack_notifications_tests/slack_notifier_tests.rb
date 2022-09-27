# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../.github/workflows/scripts/slack_notifications/slack_notifier'

class SlackNotifications < Minitest::Test
  def test_send_slack_message_zero_args
    assert_raises(ArgumentError) { SlackNotifier.send_slack_message() }
  end

  def test_send_slack_message_too_many_args
    assert_raises(ArgumentError) {
      SlackNotifier.send_slack_message("I am a notification message!", "But I'm one too many")
    }
  end

  def test_send_slack_message
    SlackNotifier.stub(:sleep, nil) do
      HTTParty.stub(:post, nil) do
        assert_nil SlackNotifier.send_slack_message("I am a notification message!")
      end
    end
  end

  def test_exit_handler_no_fail
    SlackNotifier.stub(:sleep, nil) do
      HTTParty.stub(:post, nil) do
        SlackNotifier.send_slack_message("I am a notification message!")
        assert_empty SlackNotifier.errors_array
      end
    end
  end

  def test_exit_handler_fail
    HTTParty.stub(:post, -> { raise "Yikes this didn't work!!" }) do
      SlackNotifier.send_slack_message("I am a notification message!")
      refute_empty SlackNotifier.errors_array
    end
  end
end
