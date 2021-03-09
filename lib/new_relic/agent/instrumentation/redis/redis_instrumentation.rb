# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.



module NewRelic
  module Agent
    module Instrumentation
      module Redis
        extend self

        UNKNOWN = "unknown".freeze
        LOCALHOST = "localhost".freeze

        def host_for(client)
          client.path ? LOCALHOST : client.host
        rescue => e
          NewRelic::Agent.logger.debug "Failed to retrieve Redis host: #{e}"
          UNKNOWN
        end

        def port_path_or_id_for(client)
          client.path || client.port
        rescue => e
          NewRelic::Agent.logger.debug "Failed to retrieve Redis port_path_or_id: #{e}"
          UNKNOWN
        end
      end
    end
  end
end