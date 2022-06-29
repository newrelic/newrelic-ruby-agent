# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'

if defined?(ActionController::Live)

  class UndeadController < ApplicationController
    RESPONSE_BODY = "<html><head></head><body>Brains!</body></html>"

    def brains
      render :inline => RESPONSE_BODY
    end

    def brain_stream
      render :inline => RESPONSE_BODY, :stream => true
    end
  end

  class LiveController < UndeadController
    include ActionController::Live
  end

  class ActionControllerLiveRumTest < ActionDispatch::IntegrationTest
    include MultiverseHelpers

    JS_LOADER = "JS LOADER IN DA HOUSE"

    setup_and_teardown_agent(:js_agent_loader => JS_LOADER, :beacon => "beacon", :browser_key => "key")

    def test_rum_instrumentation_when_not_streaming
      get '/undead/brains'
      assert_includes(response.body, JS_LOADER)
    end

    def test_excludes_rum_instrumentation_when_streaming_with_action_controller_live
      get '/live/brains'
      assert_equal(LiveController::RESPONSE_BODY, response.body)
    end

    def test_excludes_rum_instrumentation_when_streaming_with_action_stream_true
      get '/undead/brain_stream'

      assert_includes(response.body, UndeadController::RESPONSE_BODY)
      assert_not_includes(response.body, JS_LOADER)
    end
  end

end
