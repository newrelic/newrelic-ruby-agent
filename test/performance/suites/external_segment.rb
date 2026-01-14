# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net/http'
require 'new_relic/agent/obfuscator'

class ExternalSegment < Performance::TestCase
  ITERATIONS = 1_000

  TRACE_CONTEXT_CONFIG = {
    :'distributed_tracing.enabled' => true,
    :account_id => '190',
    :primary_application_id => '46954',
    :disable_harvest_thread => true
  }

  def setup
    NewRelic::Agent.manual_start(
      :monitor_mode => false
    )
  end

  TEST_URI = URI('http://localhost:3035/status')

  def test_external_request
    io_server = start_server
    measure(ITERATIONS) do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server(io_server)
  end

  def test_external_request_in_thread
    io_server = start_server
    measure(ITERATIONS) do
      in_transaction do
        thread = Thread.new { Net::HTTP.get(TEST_URI) }
        thread.join
      end
    end
    stop_server(io_server)
  end

  def test_external_trace_context_request
    NewRelic::Agent.config.add_config_for_testing(TRACE_CONTEXT_CONFIG)

    io_server = start_server
    measure(ITERATIONS) do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server(io_server)
  end

  def test_external_trace_context_request_within_thread
    NewRelic::Agent.config.add_config_for_testing(TRACE_CONTEXT_CONFIG)

    io_server = start_server
    measure(ITERATIONS) do
      in_transaction do
        thread = Thread.new { Net::HTTP.get(TEST_URI) }
        thread.join
      end
    end
    stop_server(io_server)
  end

  SERVER_SCRIPT_PATH = File.expand_path('../../../script/external_server.rb', __FILE__)

  def start_server
    io = IO.popen(SERVER_SCRIPT_PATH, 'r+')
    response = JSON.parse(io.gets)
    if response['message'] == 'started'
      io
    else
      fail 'Could not start server'
    end
  end

  def stop_server(io_server)
    message = {:command => 'shutdown'}.to_json
    io_server.puts message
    Process.wait
  end
end
