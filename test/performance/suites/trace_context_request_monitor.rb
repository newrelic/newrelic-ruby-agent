# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'mocha/api'

require 'new_relic/coerce'
require 'new_relic/constants'
require 'new_relic/supportability_helper'
require 'new_relic/agent/monitors'
require 'new_relic/agent/distributed_tracing'

class TraceContextRequestMonitor < Performance::TestCase
  include Mocha::API

  CONFIG = {
    :'cross_application_tracer.enabled' => false,
    :'distributed_tracing.enabled' => true,
    :encoding_key => "\0",
    :account_id => "190",
    :primary_application_id => "46954",
    :trusted_account_key => "99999"
  }

  def setup
    mocha_setup
  end

  def teardown
    mocha_teardown
  end

  def test_on_before_call
    carrier = {
      'HTTP_TRACEPARENT' => '00-12345678901234567890123456789012-1234567890123456-00',
      'HTTP_TRACESTATE' => '99999@nr=0-0-33-2827902-7d3efb1b173fecfa-e8b91a159289ff74-1-1.234567-1518469636035'
    }

    NewRelic::Agent::Transaction::DistributedTracer.any_instance.stubs(:trace_context_active?).returns(true)
    NewRelic::Agent::Transaction::DistributedTracer.any_instance.stubs(:trace_context_enabled?).returns(true)
    NewRelic::Agent.config.add_config_for_testing(CONFIG)

    @events = NewRelic::Agent::EventListener.new
    @request_monitor = NewRelic::Agent::Monitors.new(@events)

    @events.notify(:initial_configuration_complete)

    measure do
      in_transaction do
        @events.notify(:before_call, carrier)
      end
    end
  end
end
