# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'net/http'
require 'new_relic/agent/distributed_tracing/trace_context'
require 'new_relic/agent/transaction/trace_context'

class TraceContext < Performance::TestCase
  include Mocha::API

  def setup
    mocha_setup
  end

  def teardown
    mocha_teardown
  end

  CONFIG = {
    :'distributed_tracing.enabled' => true,
    :account_id => "190",
    :primary_application_id => "46954",
    :disable_harvest_thread => true
  }

  def test_parse
    carrier = {
      'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
      'tracestate' => '33@nr=0-0-33-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.234567-1518469636035'
    }

    measure do
      NewRelic::Agent::DistributedTracing::TraceContext.parse \
        carrier: carrier,
        trace_state_entry_key: "33@nr"
    end
  end

  def test_insert
    carrier = {}
    trace_id = 'a8e67265afe2773a3c611b94306ee5c2'
    parent_id = 'fb1010463ea28a38'
    trace_flags = 0x1
    trace_state = 'k1=asdf,k2=qwerty'

    measure do
      NewRelic::Agent::DistributedTracing::TraceContext.insert \
        carrier: carrier,
        trace_id: trace_id,
        parent_id: parent_id,
        trace_flags: trace_flags,
        trace_state: trace_state
    end
  end

  def test_insert_trace_context
    NewRelic::Agent.agent.stubs(:connected?).returns(true)

    carrier = {}

    with_config CONFIG do
      in_transaction do |txn|
        measure do
          txn.distributed_tracer.insert_trace_context_header carrier: carrier
        end
      end
    end
  end
end
