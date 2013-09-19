# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'
require 'new_relic/agent/commands/xray_session'

module NewRelic
  module Agent
    module Commands
      class XraySessionCollection
        extend Forwardable

        attr_reader :sessions
        def_delegators :@sessions, :[], :include?

        def initialize(new_relic_service, backtrace_service)
          @new_relic_service = new_relic_service
          @backtrace_service = backtrace_service
          @sessions = {}
        end

        def handle_active_xray_sessions(agent_command)
          incoming_ids = agent_command.arguments["xray_ids"]
          activate_sessions(incoming_ids)
          deactivate_sessions(incoming_ids)
        end

        def session_id_for_transaction_name(name)
          sessions.keys.find { |id| sessions[id].key_transaction_name == name }
        end

        def harvest_thread_profiles
          profiles = active_thread_profiling_sessions.map do |session|
            @backtrace_service.harvest(session.key_transaction_name)
          end
          profiles.compact
        end


        ## Internals

        attr_accessor :new_relic_service

        def active_thread_profiling_sessions
          sessions.values.select { |s| s.active? && s.run_profiler? }
        end

        # Session activation

        def activate_sessions(incoming_ids)
          ids_to_activate = incoming_ids - sessions.keys
          lookup_metadata_for(ids_to_activate).each do |raw|
            NewRelic::Agent.logger.debug("Adding new session for #{raw.inspect}")
            add_session(XraySession.new(raw))
          end
        end

        def lookup_metadata_for(ids_to_activate)
          return [] if ids_to_activate.empty?

          NewRelic::Agent.logger.debug("Retrieving metadata for X-Ray sessions #{ids_to_activate.inspect}")
          @new_relic_service.get_xray_metadata(ids_to_activate)
        end

        def add_session(session)
          NewRelic::Agent.logger.debug("Adding X-Ray session #{session.inspect}")
          sessions[session.id] = session
          session.activate
          if session.run_profiler?
            @backtrace_service.subscribe(session.key_transaction_name, session.command_arguments)
          end
        end

        # Session deactivation

        def deactivate_sessions(incoming_ids)
          ids_to_remove = sessions.keys - incoming_ids
          ids_to_remove.each do |session_id|
            remove_session_by_id(session_id)
          end
        end

        def remove_session_by_id(id)
          session = sessions.delete(id)

          if session
            NewRelic::Agent.logger.debug("Removing X-Ray session #{session.inspect}")
            if session.run_profiler?
              @backtrace_service.unsubscribe(session.key_transaction_name)
            end
            session.deactivate
          end
        end

      end
    end
  end
end
