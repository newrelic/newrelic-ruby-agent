# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'singleton'

module NewRelic
  class Control
    class SecurityInterface
      include Singleton

      attr_accessor :wait

      SUPPORTABILITY_PREFIX_SECURITY = 'Supportability/Ruby/SecurityAgent/Enabled/'
      SUPPORTABILITY_PREFIX_SECURITY_AGENT = 'Supportability/Ruby/SecurityAgent/Agent/Enabled/'
      ENABLED = 'enabled'
      DISABLED = 'disabled'

      def agent_started?
        (@agent_started ||= false) == true
      end

      def waiting?
        (@wait ||= false) == true
      end

      def init_agent
        return if agent_started? || waiting?

        record_supportability_metrics

        if Agent.config[:'security.agent.enabled'] && !Agent.config[:high_security]
          Agent.logger.info('Invoking New Relic security module')
          require 'newrelic_security'

          @agent_started = true
        else
          Agent.logger.info('New Relic Security is completely disabled by one of the user-provided configurations: `security.agent.enabled` or `high_security`. Not loading security capabilities.')
          Agent.logger.info("high_security = #{Agent.config[:high_security]}")
          Agent.logger.info("security.agent.enabled = #{Agent.config[:'security.agent.enabled']}")
        end
      rescue LoadError
        Agent.logger.info('New Relic security agent not found - skipping')
      rescue StandardError => exception
        Agent.logger.error("Exception in New Relic security module loading: #{exception} #{exception.backtrace}")
      end

      def record_supportability_metrics
        Agent.config[:'security.agent.enabled'] ? security_agent_metric(ENABLED) : security_agent_metric(DISABLED)
      end

      def security_agent_metric(setting)
        NewRelic::Agent.record_metric_once(SUPPORTABILITY_PREFIX_SECURITY_AGENT + setting)
      end
    end
  end
end
