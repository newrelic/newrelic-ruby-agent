# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class is the central point for dispatching get_agent_commands messages
# to the various components that actually process them.
#
# This could be evented further, but we eventually need direct access to things
# like the ThreadProfiler, so it's simpler to just keep it together here.

require 'new_relic/agent/commands/agent_command'

module NewRelic
  module Agent
    module Commands
      class AgentCommandRouter
        attr_reader :service, :handlers

        def initialize(service, thread_profiler)
          @service = service

          @handlers    = Hash.new { |*| Proc.new { |cmd| self.unrecognized_agent_command(cmd) } }

          @handlers['start_profiler'] = Proc.new { |cmd| thread_profiler.handle_start_command(cmd) }
          @handlers['stop_profiler']  = Proc.new { |cmd| thread_profiler.handle_stop_command(cmd) }
        end

        def handle_agent_commands
          results = invoke_commands(get_agent_commands)
          service.agent_command_results(results) unless results.empty?
        end

        def get_agent_commands
          commands = service.get_agent_commands
          NewRelic::Agent.logger.debug "Received get_agent_commands = #{commands.inspect}"
          commands
        end

        def invoke_commands(collector_commands)
          results = {}

          collector_commands.each do |collector_command|
            agent_command = NewRelic::Agent::Commands::AgentCommand.new(collector_command)
            results[agent_command.id.to_s] = invoke_command(agent_command)
          end

          results
        end

        class AgentCommandError < StandardError
        end

        def invoke_command(agent_command)
          begin
            call_handler_for(agent_command)
            return success
          rescue AgentCommandError => e
            error(e)
          end
        end

        SUCCESS_RESULT = {}.freeze
        ERROR_KEY = "error"

        def success
          SUCCESS_RESULT
        end

        def error(err)
          { ERROR_KEY => err.message}
        end

        def call_handler_for(agent_command)
          handler = select_handler(agent_command)
          handler.call(agent_command)
        end

        def select_handler(agent_command)
          @handlers[agent_command.name]
        end

        def unrecognized_agent_command(agent_command)
          NewRelic::Agent.logger.debug("Unrecognized agent command #{agent_command.inspect}")
        end
      end
    end
  end
end
