#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/cross_app_tracing'

class NewRelic::Agent::Instrumentation::NetInstrumentationTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :"transaction_tracer.enabled"       => true,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => 'gringletoes'
    )

    @socket = fixture_tcp_socket( @response )

    @engine = NewRelic::Agent.instance.stats_engine
    @engine.clear_stats
  end

  def test_scope_stack_integrity_maintained_on_request_failure
    @socket.stubs(:write).raises('fake network error')
    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        expected = @engine.push_scope('dummy')
        Net::HTTP.get(URI.parse('http://www.google.com/index.html')) rescue nil
        @engine.pop_scope(expected, 42)
      end
    end
  end

end
