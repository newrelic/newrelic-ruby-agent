# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/cross_app_tracing'
require 'new_relic/agent/transaction/external_request_segment'

module NewRelic
  module Agent
    module CrossAppTracing
      module NonHTTP
        extend self

        # obtain an obfuscated string suitable for delivery across public networks that identifies this application
        # and transaction to another application which is also running a New Relic agent.
        #
        # TODO: more doc
        #
        def get_request_metadata
          state = NewRelic::Agent::TransactionState.tl_get
          if txn = state.current_transaction

            # build hash of CAT metadata
            #
            rmd = {
              NewRelicID: NewRelic::Agent.config[:cross_process_id],
              NewRelicTransaction: [txn.guid, false, txn.cat_trip_id(state), txn.cat_path_hash(state)]
            }

            # add Synthetics header if we have it
            #
            rmd[:NewRelicSynthetics] = txn.raw_synthetics_header if txn.raw_synthetics_header

            # obfuscate the generated request metadata JSON
            #
            obfuscator.obfuscate ::JSON.dump(rmd)

          end
        rescue => e
          NewRelic::Agent.logger.error "error during get_request_metadata", e
        end

        # process obfuscated string indentifying a calling application and transaction that is also running a
        # New Relic agent and save information in current transaction for inclusion in a trace.
        #
        # TODO: more doc
        #
        def process_request_metadata request_metadata
          state = NewRelic::Agent::TransactionState.tl_get
          if txn = state.current_transaction
            rmd = ::JSON.parse obfuscator.deobfuscate(request_metadata)

            # handle ID
            #
            if id = rmd[NR_MESSAGE_BROKER_ID_HEADER]
              state.client_cross_app_id = id
            end

            # handle txn info
            #
            if txn_info = rmd[NR_MESSAGE_BROKER_TXN_HEADER]
              state.referring_transaction_info = txn_info
            end

            # handle synthetics
            #
            if synth = rmd[NR_MESSAGE_BROKER_SYNTHETICS_HEADER]
              txn.synthetics_payload = synth
              txn.raw_synthetics_header = obfuscator.obfuscate ::JSON.dump(synth)
            end

            nil
          end
        rescue => e
          NewRelic::Agent.logger.error "error during process_request_metadata", e
        end

        # obtain an obfuscated string suitable for delivery across public networks that carries transaction
        # information from this application to a calling application which is also running a New Relic agent.
        #
        # TODO: more doc
        #
        def get_response_metadata
          state = NewRelic::Agent::TransactionState.tl_get
          if txn = state.current_transaction

            # must freeze the name since we're responding with it
            #
            txn.freeze_name_and_execute_if_not_ignored do

              # build response payload
              #
              rmd = {
                NewRelicAppData: [
                  NewRelic::Agent.config[:cross_process_id],
                  state.timings.transaction_name,
                  state.timings.queue_time_in_seconds.to_f,
                  state.timings.app_time_in_seconds.to_f,
                  -1, # we will have no idea of the response content length at this point
                  state.request_guid
                ]
              }

              # obfuscate the generated response metadata JSON
              #
              obfuscator.obfuscate ::JSON.dump(rmd)

            end
          end
        rescue => e
          NewRelic::Agent.logger.error "error during get_response_metadata", e
        end

        EXTERNAL_TRANSACTION_PREFIX = 'ExternalTransaction/'.freeze
        SLASH = '/'.freeze
        APP_DATA_KEY = 'NewRelicAppData'.freeze

        # process obfuscated string sent from a called application that is also running a New Relic agent and
        # save information in current transaction for inclusion in a trace.
        #
        # TODO: more doc
        #
        def process_response_metadata response_metadata
          state = NewRelic::Agent::TransactionState.tl_get
          if txn = state.current_transaction
            rmd = ::JSON.parse(obfuscator.deobfuscate(response_metadata))[APP_DATA_KEY]

            # validate cross app id
            #
            if CrossAppTracing.valid_cross_app_id? rmd[0]

              # grab the current segment
              #
              if segment = txn.current_segment
                case segment
                when Transaction::ExternalRequestSegment

                  # use the ExternalRequestSegment#host method to grab this name
                  # otherwise, we have no idea of the external host at this point
                  #
                  name = EXTERNAL_TRANSACTION_PREFIX + segment.host
                  name << SLASH << rmd[0] << SLASH << rmd[1]
                  segment.name = name

                else
                  # noop
                end
              end
            end
          end

          nil
        end

        private

        def obfuscator
          CrossAppTracing.obfuscator
        end

      end
    end
  end
end
