# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/external'

module NewRelic
  module Agent
    class ExternalTest < Minitest::Test
      TRANSACTION_GUID = 'BEC1BC64675138B9'

      def setup
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)

        @obfuscator = NewRelic::Agent::Obfuscator.new('jotorotoes')
        NewRelic::Agent::CrossAppTracing.stubs(:obfuscator).returns(@obfuscator)
        NewRelic::Agent::CrossAppTracing.stubs(:valid_encoding_key?).returns(true)
      end

      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      # --- process_request_metadata

      def test_process_request_metadata_cross_app_disabled
        with_config(cat_config.merge(:'cross_application_tracer.enabled' => false)) do
          rmd = @obfuscator.obfuscate(::JSON.dump({
            NewRelicID: cat_config[:cross_process_id],
            NewRelicTransaction: ['abc', false, 'def', 'ghi']
          }))

          in_transaction do |txn|
            l = with_array_logger { NewRelic::Agent::External.process_request_metadata(rmd) }

            assert_empty l.array, 'process_request_metadata should not log errors when cross app tracing is disabled'

            refute txn.distributed_tracer.cross_app_payload
          end
        end
      end

      # --- get_response_metadata

      # ---

      def cat_config
        {
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled' => false,
          :cross_process_id => '269975#22824',
          :trusted_account_ids => [1, 269975]
        }
      end
    end
  end
end
