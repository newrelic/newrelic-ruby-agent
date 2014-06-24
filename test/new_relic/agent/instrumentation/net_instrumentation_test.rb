#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/cross_app_tracing'

class NewRelic::Agent::Instrumentation::NetInstrumentationTest < Minitest::Test
  def setup
    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :"transaction_tracer.enabled"       => true,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => 'gringletoes'
    )

    @socket = fixture_tcp_socket( @response )

    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def test_scope_stack_integrity_maintained_on_request_failure
    @socket.stubs(:write).raises('fake network error')
    with_config(:"cross_application_tracer.enabled" => true) do
      state    = NewRelic::Agent::TransactionState.tl_get
      stack    = state.traced_method_stack
      expected = stack.push_frame(state, 'dummy')
      Net::HTTP.get(URI.parse('http://www.google.com/index.html')) rescue nil
      stack.pop_frame(state, expected, 42, Time.now.to_f)
    end
  end

end
