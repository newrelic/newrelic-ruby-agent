# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require './app'

class BadInstrumentationController < ApplicationController
  # This action is intended to simulate a chunk of instrumentation that pushes
  # a traced method frame, but then never pops it. Such a situation will break
  # instrumentation of that request, but should not actually cause the request
  # to fail.
  # https://newrelic.atlassian.net/browse/RUBY-1158
  def failwhale
    state = NewRelic::Agent::TransactionState.tl_get
    stack = state.traced_method_stack
    stack.push_frame(state, 'failwhale')
    render :text => 'everything went great'
  end
end

class BadInstrumentationTest < RailsMultiverseTest
  include MultiverseHelpers
  setup_and_teardown_agent

  def test_unbalanced_tt_stack_should_not_cause_request_to_fail
    rsp = get '/bad_instrumentation/failwhale'
    assert_equal(200, rsp.to_i)
  end
end
