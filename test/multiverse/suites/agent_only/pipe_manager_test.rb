# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# https://newrelic.atlassian.net/browse/RUBY-669

class PipeManagerTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def after_setup
    @listener = NewRelic::Agent::PipeChannelManager.listener
  end

  def after_teardown
    @listener.stop
  end

  def test_old_pipes_are_cleaned_up_after_timeout
    @listener.timeout = 1
    NewRelic::Agent::PipeChannelManager.register_report_channel(:timeout_test)
    sleep 2
    @listener.start
    sleep 0.5 # give the thread some time to start, and clean things up
    refute NewRelic::Agent::PipeChannelManager.channels[:timeout_test]
  end

  def test_pipes_are_regularly_checked_for_freshness
    @listener.select_timeout = 1
    @listener.timeout = 2
    NewRelic::Agent::PipeChannelManager.register_report_channel(:select_test)

    sleep 1.5
    @listener.start
    assert NewRelic::Agent::PipeChannelManager.channels[:select_test]

    sleep 1.5
    refute NewRelic::Agent::PipeChannelManager.channels[:select_test]
  end
end
