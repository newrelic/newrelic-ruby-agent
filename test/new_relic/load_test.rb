# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'
require 'resolv'
require 'mocha/setup'

class LoadTest < Minitest::Test
  def test_loading_agent_when_disabled_does_not_resolv_addresses
    ::Resolv.expects(:getaddress).never
    ::IPSocket.expects(:getaddress).never

    require_relative '../test_helper'
  end
end
