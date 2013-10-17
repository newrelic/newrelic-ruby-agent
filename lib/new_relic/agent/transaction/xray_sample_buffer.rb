# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/transaction_sample_buffer'

module NewRelic
  module Agent
    class Transaction
      class XraySampleBuffer < TransactionSampleBuffer

        attr_writer :xray_session_collection

        def initialize
          super

          # Memoize the config setting since this happens per request
          @enabled = NewRelic::Agent.config[:'xray_session.allow_traces']
          NewRelic::Agent.config.register_callback(:'xray_session.allow_traces') do |new_value|
            @enabled = new_value
          end

          @capacity = NewRelic::Agent.config[:'xray_session.max_samples']
          NewRelic::Agent.config.register_callback(:'xray_session.max_samples') do |new_value|
            @capacity = new_value
          end
        end

        def xray_session_collection
          @xray_session_collection ||= NewRelic::Agent.instance.agent_command_router.xray_session_collection
        end

        def capacity
          @capacity
        end

        def truncate_samples
          # First in wins, so stop on allow_sample? instead of truncating
        end

        def allow_sample?(sample)
          !full? && !lookup_session_id(sample).nil?
        end

        def enabled?
          @enabled
        end


        private

        def add_sample(sample)
          super(sample)
          sample.xray_session_id = lookup_session_id(sample)
        end

        def lookup_session_id(sample)
          xray_session_collection.session_id_for_transaction_name(sample.transaction_name)
        end

      end
    end
  end
end
