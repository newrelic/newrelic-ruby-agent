# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module ForkHook
      def self.install # rubocop:disable Naming/PredicateMethod
        return false unless Process.respond_to?(:_fork) # _fork is a Ruby 3.1+ method

        Process.singleton_class.prepend(self)
        true
      end

      def self.drop_inherited_data
        agent = NewRelic::Agent.agent
        return unless agent

        agent.drop_buffered_data
        NewRelic::Agent.logger.debug("Dropped data inherited from parent process #{Process.ppid}")
      rescue StandardError => e
        begin
          NewRelic::Agent.logger.error('Failed to drop data inherited from parent process', e)
        rescue StandardError
          # Logging can raise too (e.g. when forking inside a signal trap handler).
          # We must be careful to never break an app's fork.
          nil
        end
      end

      def _fork
        pid = super
        ForkHook.drop_inherited_data if pid == 0
        pid
      end
    end
  end
end
