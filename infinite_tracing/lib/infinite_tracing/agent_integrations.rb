# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    if Config.enabled? || Config.test_framework?
      NewRelic::Agent.logger.debug "Integrating Infinite Tracer with Agent"

      require_relative 'agent_integrations/agent'
      require_relative 'agent_integrations/segment'
      require_relative 'agent_integrations/datastore_segment'
      require_relative 'agent_integrations/external_request_segment'

    else
      NewRelic::Agent.logger.debug "Skipped Integrating Infinite Tracer with Agent"
    end
  end
end