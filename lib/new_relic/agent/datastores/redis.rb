# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        MULTI_OPERATION = 'multi'
        PIPELINE_OPERATION = 'pipeline'
        BINARY_DATA_PLACEHOLDER = "<binary data>"
        MAXIMUM_ARGUMENT_LENGTH = 64
        MAXIMUM_COMMAND_LENGTH = 1000
        PRODUCT_NAME = 'Redis'
        CONNECT = 'connect'

        OBFUSCATE_ARGS = ' ?'
        ELLIPSES = '...'
        NEWLINE = "\n"

        def self.format_command(command_with_args)
          if Agent.config[:'transaction_tracer.record_redis_arguments']
            result = ""

            append_command_with_args(result, command_with_args)

            result.strip!
            result
          else
            nil
          end
        end

        def self.format_pipeline_commands(commands_with_args)
          result = ""

          commands_with_args.each do |command|
            if result.length >= MAXIMUM_COMMAND_LENGTH
              result.slice!(MAXIMUM_COMMAND_LENGTH..-4)
              result << ELLIPSES
              break
            end

            append_pipeline_command(result, command)
            result << NEWLINE
          end

          result.strip!
          result
        end

        def self.append_pipeline_command(result, command_with_args)
          if Agent.config[:'transaction_tracer.record_redis_arguments']
            append_command_with_args(result, command_with_args)
          else
            append_command_with_no_args(result, command_with_args)
          end

          result
        end

        def self.append_command_with_args(result, command_with_args)
          result << command_with_args.first.to_s

          if command_with_args.size > 1
            command_with_args[1..-1].each do |arg|
              if (result.length + MAXIMUM_ARGUMENT_LENGTH) > MAXIMUM_COMMAND_LENGTH
                # Next argument puts us over the limit...
                break
              end

              result << " #{ellipsize(arg, MAXIMUM_ARGUMENT_LENGTH)}"
            end
          end

          result
        end

        def self.append_command_with_no_args(result, command_with_args)
          result << command_with_args.first.to_s
          result << OBFUSCATE_ARGS if command_with_args.size > 1
          result
        end

        def self.is_supported_version?
          ::NewRelic::VersionNumber.new(::Redis::VERSION) >= ::NewRelic::VersionNumber.new("3.0.0")
        end

        def self.ellipsize(string, max_length)
          return string unless string.is_a?(String)

          if string.respond_to?(:encoding) && string.encoding == Encoding::ASCII_8BIT
            BINARY_DATA_PLACEHOLDER
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
