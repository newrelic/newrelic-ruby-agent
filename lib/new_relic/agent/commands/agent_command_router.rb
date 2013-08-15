# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This class is the central point for dispatching get_agent_commands messages
# to the various components that actually process them.
#
# This could be evented further, but we eventually need direct access to things
# like the ThreadProfiler, so it's simpler to just keep it together here.

module NewRelic
  module Agent
    module Commands
      class AgentCommandRouter
        attr_reader :service, :handlers

        def initialize(service, thread_profiler)
          @service = service

          @handlers = Hash.new { |*| [self, :unrecognized_agent_command] }

          @handlers['start_profiler'] = Proc.new { |args| thread_profiler.handle_start_command(args) }
          @handlers['stop_profiler'] = Proc.new { |args| thread_profiler.handle_stop_command(args) }
        end

        def handle_agent_commands
          results = invoke_commands(get_agent_commands)
          service.agent_command_results(results)
        end

        def get_agent_commands
          commands = service.get_agent_commands
          NewRelic::Agent.logger.debug "Received get_agent_commands = #{commands.inspect}"
          commands
        end

        class AgentCommandError < StandardError
        end

        def invoke_commands(commands_with_ids)
          results = {}

          commands_with_ids.each do |command_id, command|
            result = {}

            begin
              invoke_command(command)
            rescue AgentCommandError => e
              result['error'] = e.message
            end

            results[command_id.to_s] = result
          end

          results
        end

        def select_handler(command)
          name = command["name"]
          @handlers[name]
        end

        def invoke_command(command)
          handler = select_handler(command)
          handler.call(command['arguments'])
        end

        def unrecognized_agent_command(command_id, name, arguments)
          NewRelic::Agent.logger.debug("Unrecognized agent command #{name}")
        end
      end
    end
  end
end
