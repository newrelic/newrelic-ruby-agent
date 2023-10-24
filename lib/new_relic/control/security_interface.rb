# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'singleton'

module NewRelic
  class Control
    class SecurityInterface
      include Singleton

      attr_accessor :wait

      SUPPORTABILITY_METRIC = 'Supportability/Ruby/SecurityAgent/Enabled/'

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
          NewRelic::Agent.record_metric_once(SUPPORTABILITY_METRIC + 'enabled')
          require 'newrelic_security'

          @agent_started = true
        else
          Agent.logger.info('New Relic Security is completely disabled by one of the user provided config `security.agent.enabled`, `security.enabled`, or `high_security`. Not loading security capabilities.')
          NewRelic::Agent.record_metric_once(SUPPORTABILITY_METRIC + 'disabled')
        end
      rescue LoadError
        Agent.logger.info('New Relic security agent not found - skipping')
      rescue StandardError => exception
        Agent.logger.error("Exception in New Relic security module loading: #{exception} #{exception.backtrace}")
      end
    end
  end
end

# __END__

# SUPPORTABILITY_METRIC = 'Supportability/Ruby/SecurityAgent/Agent/Enabled/{enabled|disabled}'

# NewRelic::Agent.record_metric_once(SUPPORTABILITY_METRIC)

# record_metric(metric_name, value)


