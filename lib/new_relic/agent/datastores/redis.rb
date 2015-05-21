# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        def self.format_command(command_with_args)
          command = command_with_args.first

          if command_with_args.size > 1
            if Agent.config[:'transaction_tracer.record_redis_arguments']
              args = command_with_args[1..-1].map(&:inspect)
              "#{command} #{args.join(' ')}"
            else
              "#{command} ?"
            end
          else
            command.to_s
          end
        end

        def self.format_commands(commands_with_args)
          commands_with_args.map { |c| format_command(c) }.join("\n")
        end

        def self.is_supported_version?
          ::NewRelic::VersionNumber.new(::Redis::VERSION) >= ::NewRelic::VersionNumber.new("3.0.0")
        end
      end
    end
  end
end
