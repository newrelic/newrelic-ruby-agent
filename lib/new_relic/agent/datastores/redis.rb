# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        def self.format_command(command_with_args)
          command = command_with_args.first

          if Agent.config[:'transaction_tracer.record_redis_arguments']
            format_command_with_args(command, command_with_args)
          else
            nil
          end
        end

        def self.format_pipeline_command(command_with_args)
          command = command_with_args.first

          if Agent.config[:'transaction_tracer.record_redis_arguments']
            format_command_with_args(command, command_with_args)
          else
            format_command_with_no_args(command, command_with_args)
          end
        end

        def self.format_command_with_args(command, command_with_args)
          if command_with_args.size > 1
            args = command_with_args[1..-1].map(&:inspect)
            "#{command} #{args.join(' ')}"
          else
            command.to_s
          end
        end

        def self.format_command_with_no_args(command, command_with_args)
          if command_with_args.size > 1
            "#{command} ?"
          else
            command.to_s
          end
        end

        def self.format_commands(commands_with_args)
          commands_with_args.map { |cmd| format_pipeline_command(cmd) }.join("\n")
        end

        def self.is_supported_version?
          ::NewRelic::VersionNumber.new(::Redis::VERSION) >= ::NewRelic::VersionNumber.new("3.0.0")
        end
      end
    end
  end
end
