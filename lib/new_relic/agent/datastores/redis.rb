# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        MAXIMUM_ARGUMENT_LENGTH = 64
        PRODUCT_NAME = 'Redis'.freeze

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
            args = command_with_args[1..-1].map do |arg|
              ellipsize(arg, MAXIMUM_ARGUMENT_LENGTH)
            end

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

        def self.ellipsize(string, max_length)
          return string unless string.is_a?(String)

          if string.encoding == Encoding::ASCII_8BIT
            "<binary data>"
          elsif string.length > max_length
            chunk_size   = (max_length - 5) / 2
            prefix_range = (0...chunk_size)
            suffix_range = (-chunk_size..-1)

            prefix = string[prefix_range]
            suffix = string[suffix_range]

            "\"#{prefix}...#{suffix}\""
          else
            string.dump
          end
        end
      end
    end
  end
end
