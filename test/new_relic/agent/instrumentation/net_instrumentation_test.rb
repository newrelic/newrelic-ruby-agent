#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'net/http'
require File.expand_path '../../../../test_helper', __FILE__
require 'new_relic/agent/distributed_tracing/cross_app_tracing'

class NewRelic::Agent::Instrumentation::NetInstrumentationTest < Minitest::Test
  def setup
    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :"transaction_tracer.enabled"       => true,
      :cross_process_id                   => '269975#22824',
      :encoding_key                       => 'gringletoes'
    )

    @response ||= nil

    @socket = fixture_tcp_socket( @response )

    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_scope_stack_integrity_maintained_on_request_failure
    @socket.stubs(:write).raises('fake network error')
    @socket.stubs(:write_nonblock).raises('fake network error')
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction "test" do
        segment = NewRelic::Agent::Tracer.start_segment name: "dummy"
        Net::HTTP.get(URI.parse('http://www.google.com/index.html')) rescue nil
        segment.finish
      end
    end
  end
end
