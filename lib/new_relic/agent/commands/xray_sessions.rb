# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'
require 'new_relic/agent/commands/xray_session'

module NewRelic
  module Agent
    module Commands
      class XraySessions
        extend Forwardable

        attr_reader :sessions
        def_delegators :@sessions, :[], :include?

        def initialize(service)
          @service = service
          @sessions = {}
        end

        def handle_active_xray_sessions(agent_command)
          incoming_ids = agent_command.arguments["xray_ids"]
          activate_sessions(incoming_ids)
          deactivate_sessions(incoming_ids)
        end


        private

        attr_reader :service

        # Session activation

        def activate_sessions(incoming_ids)
          ids_to_activate = select_to_add(incoming_ids)
          lookup_metadata_for(ids_to_activate).each do |raw|
            NewRelic::Agent.logger.debug("Adding new session for #{raw.inspect}")
            add_session(XraySession.new(raw))
          end
        end

        def select_to_add(incoming_ids)
          incoming_ids.reject {|id| sessions.include?(id)}
        end

        def lookup_metadata_for(ids_to_activate)
          return [] if ids_to_activate.empty?

          NewRelic::Agent.logger.debug("Retrieving metadata for X-Ray sessions #{ids_to_activate.inspect}")
          @service.get_xray_metadata(ids_to_activate)
        end

        def add_session(session)
          NewRelic::Agent.logger.debug("Adding X-Ray session #{session.inspect}")
          sessions[session.id] = session
          session.activate
        end

        # Session deactivations

        def deactivate_sessions(incoming_ids)
          select_to_remove(incoming_ids).each do |inactive_session|
            remove_session(inactive_session)
          end
        end

        def select_to_remove(incoming_ids)
          inactive_pairs = sessions.reject {|k, _| incoming_ids.include?(k)}
          inactive_pairs.map {|p| p.last}
        end

        def remove_session(session)
          NewRelic::Agent.logger.debug("Removing X-Ray session #{session.inspect}")
          sessions.delete(session.id)
          session.deactivate
        end

      end
    end
  end
end
