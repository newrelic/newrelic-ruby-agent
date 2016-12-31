#!/usr/bin/ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

$:.unshift File.expand_path('../../../lib', __FILE__)
$:.unshift File.expand_path('../..', __FILE__)

require 'newrelic_rpm'
require 'agent_helper'
require 'new_relic/fake_external_server'
require 'net/http'

STDOUT.sync = true

server = NewRelic::FakeExternalServer.new(3035)
server.reset
server.run

puts "ready..."

while command = gets.chomp do
  if command == "shutdown"
    server.stop
    puts "done..."
    exit(0)
  end
end
