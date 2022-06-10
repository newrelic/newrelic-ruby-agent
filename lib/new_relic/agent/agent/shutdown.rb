# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Shutdown
      # Attempt a graceful shutdown of the agent, flushing any remaining
      # data.
      def shutdown
        return unless started?
        ::NewRelic::Agent.logger.info "Starting Agent shutdown"

        stop_event_loop
        trap_signals_for_litespeed
        untraced_graceful_disconnect
        revert_to_default_configuration

        @started = nil
        Control.reset
      end

      def untraced_graceful_disconnect
        begin
          NewRelic::Agent.disable_all_tracing do
            graceful_disconnect
          end
        rescue => e
          ::NewRelic::Agent.logger.error e
        end
      end
    end
  end
end
