# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'
require 'rails/test_help'
require 'multiverse_helpers'

class BadInstrumentationController < ApplicationController
  include Rails.application.routes.url_helpers

  # This action is intended to simulate a chunk of instrumentation that pushes
  # a TT scope, but then never pops it. Such a situation will break
  # instrumentation of that request, but should not actually cause the request
  # to fail.
  # https://newrelic.atlassian.net/browse/RUBY-1158
  def failwhale
    NewRelic::Agent.instance.stats_engine.push_scope('failwhale', Time.now)
    render :text => 'everything went great'
  end
end

class BadInstrumentationTest < ActionDispatch::IntegrationTest
  include MultiverseHelpers
  setup_and_teardown_agent

  def test_unbalanced_tt_stack_should_not_cause_request_to_fail
    rsp = get '/bad_instrumentation/failwhale'
    assert_equal(200, rsp.to_i)
  end
end
