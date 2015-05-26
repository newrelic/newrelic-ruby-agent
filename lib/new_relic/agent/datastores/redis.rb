# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        MAXIMUM_ARGUMENT_LENGTH = 64

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
          if string.length > max_length
            chunk_size = (max_length - 5) / 2
            prefix_range = (0...chunk_size)
            suffix_range = (-chunk_size..-1)

            prefix = string[prefix_range].dump
            suffix = string[suffix_range].dump

            # The dump above adds double-quotes around the string, and expands
            # non-printable characters, into escape sequences, so this second
            # slice chops off the trailing double-quote on the prefix and
            # leading double-quote on the suffix, and keeps us a reasonable
            # length when escape characters are present.
            #
            # We do this in two phases to avoid calling #dump against the entire
            # input string if it is very large, which would result in a giant
            # temporary string being created, of which we only want the prefix
            # and suffix.
            prefix = prefix[prefix_range]
            suffix = suffix[suffix_range]

            "#{prefix}...#{suffix}"
          else
            string.dump
          end
        end
      end
    end
  end
end
