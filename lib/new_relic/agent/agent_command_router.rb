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
    class AgentCommandRouter
      attr_reader :thread_profiler

      def initialize(thread_profiler=nil)
        @handlers = Hash.new { |*_| [self, :unrecognized_agent_command] }

        add_handler("start_profiler", thread_profiler, :handle_start_command)
        add_handler("stop_profiler",  thread_profiler, :handle_stop_command)
      end

      def add_handler(name, handler, message)
        @handlers[name] = [handler, message]
      end

      def check_for_agent_commands(service)
        commands = service.get_agent_commands
        NewRelic::Agent.logger.debug "Received get_agent_commands = #{commands.inspect}"

        commands.each do |cmd|
          # TODO: Aggregate results from multiple commands in same batch to send back?
          route_command(cmd) do |command_id, error|
            service.agent_command_results(command_id, error)
          end
        end
      end

      def route_command(incoming_command, &results_callback)
        #TODO: Validate command format?
        command_id, command = incoming_command

        name = command["name"]
        arguments = command["arguments"]

        handler, message = @handlers[name]
        handler.send(message, command_id, name, arguments, &results_callback)
      end

      def unrecognized_agent_command(command_id, name, arguments)
        NewRelic::Agent.logger.debug("Unrecognized agent command #{name}")
      end
    end
  end
end
