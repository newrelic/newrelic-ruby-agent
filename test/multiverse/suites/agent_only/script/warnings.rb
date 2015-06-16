#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'bundler/setup'
require 'newrelic_rpm'

NewRelic::Agent::Transaction.wrap(NewRelic::Agent::TransactionState.tl_get, 'ponies', :controller) do
end

NewRelic::Agent.notice_error 'oops'

NewRelic::Agent.instance.send(:transmit_data)

puts NewRelic::VERSION::STRING
