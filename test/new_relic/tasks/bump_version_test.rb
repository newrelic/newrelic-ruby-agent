# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

module NewRelic
  # mostly this class just passes through to the active agent
  # through the agent method or the control instance through
  # NewRelic::Control.instance . But it's nice to make sure.
  class MainAgentTest < Minitest::Test
  end
end
