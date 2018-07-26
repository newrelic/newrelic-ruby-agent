# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'json'

module NewRelic
  module Agent
    module CrossAppTracing

      # The cross app response header for "outgoing" calls
      NR_APPDATA_HEADER = 'X-NewRelic-App-Data'.freeze

      # The cross app id header for "outgoing" calls
      NR_ID_HEADER = 'X-NewRelic-ID'.freeze

      # The cross app transaction header for "outgoing" calls
      NR_TXN_HEADER = 'X-NewRelic-Transaction'.freeze

      NR_MESSAGE_BROKER_ID_HEADER  = 'NewRelicID'.freeze
      NR_MESSAGE_BROKER_TXN_HEADER = 'NewRelicTransaction'.freeze
      NR_MESSAGE_BROKER_SYNTHETICS_HEADER = 'NewRelicSynthetics'.freeze

      ###############
      module_function
      ###############

      def cross_app_enabled?
        valid_cross_process_id? &&
          valid_encoding_key? &&
          cross_application_tracer_enabled?
      end

      def valid_cross_process_id?
        if NewRelic::Agent.config[:cross_process_id] && NewRelic::Agent.config[:cross_process_id].length > 0
          true
        else
          NewRelic::Agent.logger.debug "No cross_process_id configured"
          false
        end
      end

      def valid_encoding_key?
        if NewRelic::Agent.config[:encoding_key] && NewRelic::Agent.config[:encoding_key].length > 0
          true
        else
          NewRelic::Agent.logger.debug "No encoding_key set"
          false
        end
      end

      def cross_application_tracer_enabled?
        !NewRelic::Agent.config[:"distributed_tracing.enabled"] &&
          (NewRelic::Agent.config[:"cross_application_tracer.enabled"] ||
           NewRelic::Agent.config[:cross_application_tracing])
      end

      def obfuscator
        @obfuscator ||= NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
      end

      def insert_request_headers request, txn_guid, trip_id, path_hash
        cross_app_id = NewRelic::Agent.config[:cross_process_id]
        txn_data  = ::JSON.dump([txn_guid, false, trip_id, path_hash])

        request[NR_ID_HEADER]  = obfuscator.obfuscate(cross_app_id)
        request[NR_TXN_HEADER] = obfuscator.obfuscate(txn_data)
      end

      def response_has_crossapp_header?(response)
        if !!response[NR_APPDATA_HEADER]
          true
        else
          NewRelic::Agent.logger.debug "No #{NR_APPDATA_HEADER} header"
          false
        end
      end

      # Extract x-process application data from the specified +response+ and return
      # it as an array of the form:
      #
      #  [
      #    <cross app ID>,
      #    <transaction name>,
      #    <queue time in seconds>,
      #    <response time in seconds>,
      #    <request content length in bytes>,
      #    <transaction GUID>
      #  ]
      def extract_appdata(response)
        appdata = response[NR_APPDATA_HEADER]

        decoded_appdata = obfuscator.deobfuscate(appdata)
        decoded_appdata.set_encoding(::Encoding::UTF_8) if
          decoded_appdata.respond_to?(:set_encoding)

        ::JSON.load(decoded_appdata)
      end

      def valid_cross_app_id?(xp_id)
        !!(xp_id =~ /\A\d+#\d+\z/)
      end

      def insert_message_headers headers, txn_guid, trip_id, path_hash, synthetics_header
        headers[NR_MESSAGE_BROKER_ID_HEADER]  = obfuscator.obfuscate(NewRelic::Agent.config[:cross_process_id])
        headers[NR_MESSAGE_BROKER_TXN_HEADER] = obfuscator.obfuscate(::JSON.dump([txn_guid, false, trip_id, path_hash]))
        headers[NR_MESSAGE_BROKER_SYNTHETICS_HEADER] = synthetics_header if synthetics_header
      end

      def message_has_crossapp_request_header? headers
        !!headers[NR_MESSAGE_BROKER_ID_HEADER]
      end

      def reject_messaging_cat_headers headers
        headers.reject {|k,_| k == NR_MESSAGE_BROKER_ID_HEADER || k == NR_MESSAGE_BROKER_TXN_HEADER}
      end

      def trusts? id
        split_id = id.match(/(\d+)#\d+/)
        return false if split_id.nil?

        NewRelic::Agent.config[:trusted_account_ids].include? split_id.captures.first.to_i
      end

      def trusted_valid_cross_app_id? id
        valid_cross_app_id?(id) && trusts?(id)
      end

      def assign_intrinsic_transaction_attributes state
        # We expect to get the before call to set the id (if we have it) before
        # this, and then write our custom parameter when the transaction starts
        return unless transaction = state.current_transaction

        if state.client_cross_app_id
          transaction.attributes.add_intrinsic_attribute(:client_cross_process_id, state.client_cross_app_id)
        end

        if referring_guid = state.referring_transaction_info && state.referring_transaction_info[0]
          transaction.attributes.add_intrinsic_attribute(:referring_transaction_guid, referring_guid)
        end
      end
    end
  end
end
