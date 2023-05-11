require 'singleton'

module NewRelic
  class Control
    class SecurityInterface
      include Singleton

      attr_accessor :wait

      def agent_started?
        @agent_started == true
      end

      def waiting?
        @wait == true
      end

      def init_agent
        return if agent_started? || waiting?

        if Agent.config[:'security.agent.enabled']
          Agent.logger.info('Invoking New Relic security module')
          require 'newrelic_security'

          @agent_started = true
        else
          Agent.logger.info('New Relic security module is disabled.')
        end
      rescue LoadError
        Agent.logger.info('New Relic security agent not found - skipping')
      rescue StandardError => exception
        Agent.logger.error("Exception in New Relic security module loading: #{exception} #{exception.backtrace}")
      end
    end
  end
end
