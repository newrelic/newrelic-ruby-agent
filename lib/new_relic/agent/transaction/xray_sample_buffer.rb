# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_sample_buffer'

module NewRelic
  module Agent
    class Transaction
      class XraySampleBuffer < TransactionSampleBuffer

        attr_writer :xray_sessions

        def xray_sessions
          @xray_sessions ||= NewRelic::Agent.instance.agent_command_router.xray_sessions
        end

        MAX_SAMPLES = 10

        def max_samples
          MAX_SAMPLES
        end

        def truncate_samples
          # First in wins, so stop on allow_sample? instead of truncating
        end

        def allow_sample?(sample)
          !full? && !lookup_session_id(sample).nil?
        end


        private

        def add_sample(sample)
          super(sample)
          sample.xray_session_id = lookup_session_id(sample)
        end

        def lookup_session_id(sample)
          xray_sessions.session_id_for_transaction_name(sample.transaction_name)
        end

      end
    end
  end
end
