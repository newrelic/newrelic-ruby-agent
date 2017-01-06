#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../..', __FILE__)

require 'newrelic_rpm'
require 'agent_helper'
require 'new_relic/fake_external_server'
require 'net/http'
require 'json'

STDOUT.sync = true

server = NewRelic::FakeExternalServer.new(3035)
server.reset
server.run

puts JSON.dump({:message => "started"})

while message = JSON.parse(gets) do
  case message["command"]
  when "shutdown"
    server.stop
    exit(0)
  when "add_headers"
    server.override_response_headers message["payload"]
  end
end
