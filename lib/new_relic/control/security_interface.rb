# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'singleton'

module NewRelic
  class Control
    class SecurityInterface
      include Singleton

      attr_accessor :wait

      def agent_started?
        (@agent_started ||= false) == true
      end

      def waiting?
        (@wait ||= false) == true
      end

      def init_agent
        return if agent_started? || waiting?

        if Agent.config[:'security.agent.enabled'] && Agent.config[:'security.enabled'] && !Agent.config[:high_security]
          Agent.logger.info('Invoking New Relic security module')
          require 'newrelic_security'

          @agent_started = true
        else
          Agent.logger.info('New Relic Security is completely disabled by one of the user provided config `security.agent.enabled`, `security.enabled`, or `high_security`. Not loading security capabilities.')
        end
      rescue LoadError
        Agent.logger.info('New Relic security agent not found - skipping')
      rescue StandardError => exception
        Agent.logger.error("Exception in New Relic security module loading: #{exception} #{exception.backtrace}")
      end
    end
  end
end
