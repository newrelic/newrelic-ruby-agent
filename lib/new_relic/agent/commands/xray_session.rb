# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Commands
      class XraySession
        attr_reader :id, :active
        attr_reader :xray_session_name, :key_transaction_name, :run_profiler,
                    :requested_trace_count, :duration, :sample_period,
                    :thread_profile

        alias_method :active?, :active

        def initialize(raw_session)
          @id                    = raw_session.fetch("x_ray_id", nil)
          @xray_session_name     = raw_session.fetch("xray_session_name", "")
          @key_transaction_name  = raw_session.fetch("key_transaction_name", "")
          @requested_trace_count = raw_session.fetch("requested_trace_count", 100)
          @duration              = raw_session.fetch("duration", 86400)
          @sample_period         = raw_session.fetch("sample_period", 0.1)
          @run_profiler          = raw_session.fetch("run_profiler", true)

          if @run_profiler
            @thread_profile = NewRelic::Agent::Threading::ThreadProfile.new(raw_session)
          end
        end

        def activate
          @active = true
        end

        def deactivate
          @active = false
        end
      end
    end
  end
end
