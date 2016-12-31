# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'net/http'

class ExternalSegment < Performance::TestCase

  CONFIG = {
      :license_key     => 'a' * 40,
      :developer_mode  => false,
      :'cross_application_tracer.enabled' => true,
      :cross_process_id                   => "1#1884",
      :encoding_key                       => "jotorotoes",
      :trusted_account_ids                => [1]
  }

  def setup
    NewRelic::Agent.config.add_config_for_testing(CONFIG)

    NewRelic::Agent.manual_start(
      :developer_mode => false,
      :monitor_mode   => false
    )
  end

  TEST_URI = URI("http://localhost:3035/status")

  def test_external_request
    server_process = start_server
    measure do
      in_transaction do
        Net::HTTP.get(TEST_URI)
      end
    end
    stop_server server_process
  end

  SERVER_SCRIPT_PATH = File.expand_path('../../../script/external_server.rb', __FILE__)

  def start_server
    io = IO.popen(SERVER_SCRIPT_PATH, 'r+')
    if io.gets.chomp == "ready..."
      io
    else
      fail "Could not start server"
    end
  end

  def stop_server server_process
    server_process.puts "shutdown"
    Process.wait
  end
end
