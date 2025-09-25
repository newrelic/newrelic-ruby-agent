# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../.github/workflows/scripts/slack_notifications/slack_notifier'

class SlackNotifierTests < Minitest::Test
  def clear_errors_array
    SlackNotifier.errors_array.clear
  end

  def test_send_slack_message_zero_args
    assert_raises(ArgumentError) { SlackNotifier.send_slack_message() }
  end

  def test_send_slack_message_too_many_args
    assert_raises(ArgumentError) {
      SlackNotifier.send_slack_message('I am a notification message!', "But I'm one too many")
    }
  end

  def test_send_slack_message
    SlackNotifier.stub(:sleep, nil) do
      HTTParty.stub(:post, nil) do
        assert_nil SlackNotifier.send_slack_message('I am a notification message!')
      end
    end
  end

  def test_errors_array_no_errors
    SlackNotifier.stub(:sleep, nil) do
      HTTParty.stub(:post, nil) do
        SlackNotifier.send_slack_message('I am a notification message!')

        assert_empty SlackNotifier.errors_array
      end
    end
  end

  def test_errors_array_one_error
    HTTParty.stub(:post, -> { raise "Yikes this didn't work!!" }) do
      SlackNotifier.send_slack_message('I am a notification message!')

      assert_equal 1, SlackNotifier.errors_array.length
    end
    clear_errors_array
  end

  def test_errors_array_multiple_errors
    HTTParty.stub(:post, -> { raise "Yikes this didn't work!!" }) do
      SlackNotifier.send_slack_message('I am a notification message!')
      SlackNotifier.send_slack_message('I am a another notification message!')

      assert_equal 2, SlackNotifier.errors_array.length
    end
    clear_errors_array
  end

  def test_report_errors_empty
    assert_nil SlackNotifier.report_errors
  end

  def test_report_errors_one
    SlackNotifier.errors_array << 'SomeError'
    exception = assert_raises StandardError do
      SlackNotifier.report_errors
    end

    assert_equal('SomeError', exception.message)
    clear_errors_array
  end

  def test_report_errors_multiple_errors
    SlackNotifier.errors_array << 'SomeError'
    SlackNotifier.errors_array << 'AnotherError'
    exception = assert_raises StandardError do
      SlackNotifier.report_errors
    end

    assert_equal("SomeError\nAnotherError", exception.message)
    clear_errors_array
  end
end
