# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'monitors/inbound_request_monitor'

require_relative 'monitors/synthetics_monitor'

require_relative 'monitors/cross_app_monitor'
require_relative 'monitors/distributed_trace_monitor'
require_relative 'monitors/trace_context_request_monitor'

module NewRelic
  module Agent
    class Monitors
      attr_reader :cross_app_monitor

      def initialize events
        @synthetics_monitor        = NewRelic::Agent::SyntheticsMonitor.new events
      
        @cross_app_monitor         = NewRelic::Agent::DistributedTracing::CrossAppMonitor.new events
        @distributed_trace_monitor = NewRelic::Agent::DistributedTracing::DistributedTraceMonitor.new events
        @trace_context_monitor     = NewRelic::Agent::DistributedTracing::TraceContextRequestMonitor.new events
      end

    end
  end
end