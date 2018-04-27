# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'
require 'new_relic/agent/obfuscator'

class ExternalSegment < Performance::TestCase

  CONFIG = {
      :license_key     => 'a' * 40,
      :'cross_application_tracer.enabled' => true,
      :cross_process_id                   => "1#1884",
      :encoding_key                       => "jotorotoes",
      :trusted_account_ids                => [1]
  }

  def setup
    NewRelic::Agent.config.add_config_for_testing(CONFIG)

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
    io_server = start_server
    reply_with_cat_headers io_server
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

  def reply_with_cat_headers io_server
    message = {
      :command => "add_headers",
      :payload => cat_response_headers
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
end
