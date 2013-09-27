# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'

module NewRelic
  module Agent
    module Commands
      class XraySession
        extend Forwardable

        attr_reader :id, :command_arguments
        attr_reader :xray_session_name, :key_transaction_name,
                    :requested_trace_count, :duration, :sample_period

        def initialize(command_arguments)
          @command_arguments     = command_arguments
          @id                    = command_arguments.fetch("x_ray_id", nil)
          @xray_session_name     = command_arguments.fetch("xray_session_name", "")
          @key_transaction_name  = command_arguments.fetch("key_transaction_name", "")
          @requested_trace_count = command_arguments.fetch("requested_trace_count", 100)
          @duration              = command_arguments.fetch("duration", 86400)
          @sample_period         = command_arguments.fetch("sample_period", 0.1)
          @run_profiler          = command_arguments.fetch("run_profiler", true)
        end

        def active?
          @active
        end

        def run_profiler?
          @run_profiler && NewRelic::Agent.config[:'xray_session.allow_profiles']
        end

        def activate
          @active = true
          @start_time = Time.now
        end

        def deactivate
          @active = false
        end

        def requested_period
          @sample_period
        end

        def finished?
          @start_time + @duration < Time.now
        end
      end
    end
  end
end
