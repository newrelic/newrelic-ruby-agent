# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/datastores/mongo/event_formatter'

module NewRelic
  module Agent
    module Instrumentation
      class MongodbCommandSubscriber
        MONGODB = 'MongoDB'.freeze
        COLLECTION = "collection".freeze

        def started(event)
          begin
            return unless NewRelic::Agent.tl_is_execution_traced?
            segments[event.operation_id] = start_segment event
          rescue Exception => e
            log_notification_error('started', e)
          end
        end

        def completed(event)
          begin
            state = NewRelic::Agent::TransactionState.tl_get
            return unless state.is_execution_traced?
            segment = segments.delete(event.operation_id)
            segment.finish if segment
          rescue Exception => e
            log_notification_error('completed', e)
          end
        end

        alias :succeeded :completed
        alias :failed :completed

        private

        def start_segment event
          host = host_from_address event.address
          port_path_or_id = port_path_or_id_from_address event.address
          segment = NewRelic::Agent::Transaction.start_datastore_segment(
            product: MONGODB,
            operation: event.command_name,
            collection: collection(event),
            host: host,
            port_path_or_id: port_path_or_id,
            database_name: event.database_name
          )
          segment.notice_nosql_statement(generate_statement(event))
          segment
        end

        def collection(event)
          event.command[COLLECTION] || event.command[:collection] || event.command.values.first
        end

        def log_notification_error(event_type, error)
          NewRelic::Agent.logger.error("Error during MongoDB #{event_type} event:")
          NewRelic::Agent.logger.log_exception(:error, error)
        end

        def segments
          @segments ||= {}
        end

        def generate_statement(event)
          NewRelic::Agent::Datastores::Mongo::EventFormatter.format(
            event.command_name,
            event.database_name,
            event.command
          )
        end

        UNKNOWN = "unknown".freeze
        LOCALHOST = "localhost".freeze

        def host_from_address(address)
          if unix_domain_socket? address.host
            LOCALHOST
          else
            address.host
          end
        rescue => e
          NewRelic::Agent.logger.debug "Failed to retrieve Mongo host: #{e}"
          UNKNOWN
        end

        def port_path_or_id_from_address(address)
          if unix_domain_socket? address.host
            address.host
          else
            address.port
          end
        rescue => e
          NewRelic::Agent.logger.debug "Failed to retrieve Mongo port_path_or_id: #{e}"
          UNKNOWN
        end

        SLASH = "/".freeze

        def unix_domain_socket?(host)
          host.start_with? SLASH
        end
      end
    end
  end
end
