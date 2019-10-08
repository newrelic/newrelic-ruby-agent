# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'
require 'new_relic/agent/obfuscator'

class ExternalSegment < Performance::TestCase

  CAT_CONFIG = {
      :license_key     => 'a' * 40,
      :'cross_application_tracer.enabled' => true,
      :cross_process_id                   => "1#1884",
      :encoding_key                       => "jotorotoes",
      :trusted_account_ids                => [1]
  }

  TRACE_CONTEXT_CONFIG = {
      :'trace_context.enabled' => true,
      :account_id => "190",
      :primary_application_id => "46954",
      :disable_harvest_thread => true
  }

  def setup

    NewRelic::Agent.manual_start(
      :monitor_mode   => false
    )
  end

  TEST_URI = URI("http://localhost:3035/status")

  def test_external_request
    io_server = start_server
    measure do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server io_server
  end

  def test_external_cat_request
    NewRelic::Agent.config.add_config_for_testing(CAT_CONFIG)

    io_server = start_server
    reply_with_headers io_server, cat_response_headers
    measure do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server io_server
  end

  def test_external_trace_context_request
    NewRelic::Agent.config.add_config_for_testing(TRACE_CONTEXT_CONFIG)

    io_server = start_server
    reply_with_headers io_server, trace_context_response_headers
    measure do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server io_server
  end

  SERVER_SCRIPT_PATH = File.expand_path('../../../script/external_server.rb', __FILE__)

  def start_server
  io = IO.popen(SERVER_SCRIPT_PATH, 'r+')
    response = JSON.parse(io.gets)
    if response["message"] == "started"
      io
    else
      fail "Could not start server"
    end
  end

  def reply_with_headers io_server, headers
    message = {
      :command => "add_headers",
      :payload => headers
    }.to_json
    io_server.puts message
  end

  def stop_server io_server
    message = {:command => "shutdown"}.to_json
    io_server.puts message
    Process.wait
  end

  def cat_response_headers
    obfuscator = NewRelic::Agent::Obfuscator.new NewRelic::Agent.config[:encoding_key]
    app_data = obfuscator.obfuscate(["1#1884", "txn-name", 2, 8, 0, 'BEC1BC64675138B9'].to_json) + "\n"
    {'X-NewRelic-App-Data' => app_data}
  end

  def trace_context_response_headers
    {
      'traceparent' =>'00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
      'tracestate' => '33@nr=0-0-33-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.234567-1518469636035'
    }
  end
end
