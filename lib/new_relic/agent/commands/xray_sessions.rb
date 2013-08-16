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

        def initialize
          @sessions = {}
        end

        def active_sessions(raw_sessions)
          incoming_sessions = raw_sessions.map {|raw| XraySession.new(raw)}
          add_active_sessions(incoming_sessions)
          remove_inactive_sessions(incoming_sessions)
        end

        private

        def add_active_sessions(incoming_sessions)
          incoming_sessions.each do |incoming_session|
            if !sessions.include?(incoming_session.id)
              sessions[incoming_session.id] = incoming_session
              incoming_session.activate
            end
          end
        end

        def remove_inactive_sessions(incoming_sessions)
          inactive_sessions = find_inactive_sessions(incoming_sessions)
          inactive_sessions.each do |inactive_session|
            sessions.delete(inactive_session.id)
            inactive_session.deactivate
          end
        end

        def find_inactive_sessions(incoming_sessions)
          active_keys = incoming_sessions.map {|s| s.id}
          inactive_pairs = sessions.reject {|k, _| active_keys.include?(k)}
          inactive_pairs.map {|p| p.last}
        end
      end
    end
  end
end
