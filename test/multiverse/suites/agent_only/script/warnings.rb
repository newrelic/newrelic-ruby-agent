#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require 'bundler/setup'
require 'newrelic_rpm'

NewRelic::Agent::Tracer.in_transaction(name: 'ponies', category: :controller) do
end

NewRelic::Agent.notice_error 'oops'

NewRelic::Agent.instance.send(:transmit_data)

puts NewRelic::VERSION::STRING
