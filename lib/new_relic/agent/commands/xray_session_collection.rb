# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'
require 'thread'
require 'new_relic/agent/commands/xray_session'

module NewRelic
  module Agent
    module Commands
      class XraySessionCollection
        extend Forwardable

        def initialize(backtrace_service, event_listener)
          @backtrace_service = backtrace_service

          # This lock protects access to the sessions hash, but it's expected
          # that individual session objects within the hash will be manipulated
          # outside the lock.  This is safe because manipulation of the session
          # objects is expected from only a single thread (the harvest thread)
          @sessions_lock = Mutex.new
          @sessions = {}

          if event_listener
            event_listener.subscribe(:before_harvest, &method(:cleanup_finished_sessions))
          end
        end

        def handle_active_xray_sessions(agent_command)
          # If X-Rays are disabled, just be quiet about it and don't start the
          # command. Other hosts might be running the X-Ray, so we don't need
          # to bark on every get_agent_commands.
          if !NewRelic::Agent.config[:'xray_session.enabled']
            NewRelic::Agent.logger.debug("Not responding to X-Ray command because of config 'xray_session.enabled' = #{NewRelic::Agent.config[:'xray_session.enabled']}")
            return
          end

          incoming_ids = agent_command.arguments["xray_ids"]
          deactivate_for_incoming_sessions(incoming_ids)
          activate_sessions(incoming_ids)
        end

        def session_id_for_transaction_name(name)
          @sessions_lock.synchronize do
            @sessions.each do |id, session|
              return id if session.key_transaction_name == name
            end
          end
          nil
        end

        NO_PROFILES = [].freeze

        def harvest_thread_profiles
          return NO_PROFILES unless NewRelic::Agent::Threading::BacktraceService.is_supported?

          profiles = active_thread_profiling_sessions.map do |session|
            NewRelic::Agent.logger.debug("Harvesting profile for X-Ray session #{session.inspect}")
            @backtrace_service.harvest(session.key_transaction_name)
          end
          profiles.reject! {|p| p.empty?}
          profiles.compact
        end

        def stop_all_sessions
          deactivate_for_incoming_sessions([])
        end

        def cleanup_finished_sessions
          finished_session_ids.each do |id|
            NewRelic::Agent.logger.debug("Finished X-Ray session #{id} by duration. Removing it from active sessions.")
            remove_session_by_id(id)
          end
        end


        ### Internals

        def new_relic_service
          NewRelic::Agent.instance.service
        end

        # These are unsynchonized and should only be used for testing
        def_delegators :@sessions, :[], :include?

        def active_thread_profiling_sessions
          @sessions_lock.synchronize do
            @sessions.values.select { |s| s.active? && s.run_profiler? }
          end
        end

        ### Session activation

        def activate_sessions(incoming_ids)
          lookup_metadata_for(ids_to_activate(incoming_ids)).each do |raw|
            add_session(XraySession.new(raw))
          end
        end

        def ids_to_activate(incoming_ids)
          @sessions_lock.synchronize { incoming_ids - @sessions.keys }
        end

        # Please don't hold the @sessions_lock across me! Calling the service
        # is time-consuming, and will block request threads. Which is rude.
        def lookup_metadata_for(ids_to_activate)
          return [] if ids_to_activate.empty?

          NewRelic::Agent.logger.debug("Retrieving metadata for X-Ray sessions #{ids_to_activate.inspect}")
          new_relic_service.get_xray_metadata(ids_to_activate)
        end

        def add_session(session)
          NewRelic::Agent.logger.debug("Adding X-Ray session #{session.inspect}")
          NewRelic::Agent.increment_metric("Supportability/XraySessions/Starts")

          @sessions_lock.synchronize { @sessions[session.id] = session }

          session.activate
          if session.run_profiler?
            @backtrace_service.subscribe(session.key_transaction_name, session.command_arguments)
          end
        end

        ### Session deactivation

        def deactivate_for_incoming_sessions(incoming_ids)
          ids_to_remove(incoming_ids).each do |session_id|
            remove_session_by_id(session_id)
          end
        end

        def ids_to_remove(incoming_ids)
          @sessions_lock.synchronize { @sessions.keys - incoming_ids }
        end

        def remove_session_by_id(id)
          session = @sessions_lock.synchronize { @sessions.delete(id) }

          if session
            NewRelic::Agent.logger.debug("Removing X-Ray session #{session.inspect}")
            NewRelic::Agent.increment_metric("Supportability/XraySessions/Stops")

            if session.run_profiler?
              @backtrace_service.unsubscribe(session.key_transaction_name)
            end
            session.deactivate
          end
        end

        def finished_session_ids
          @sessions_lock.synchronize do
            @sessions.map{|k, s| k if s.finished?}.compact
          end
        end

      end
    end
  end
end
