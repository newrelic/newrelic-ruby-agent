# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'

require 'newrelic_rpm'

NewRelic::Agent.logger.debug "Detected New Relic Infinite Tracing Gem"

require 'new_relic/infinite_tracing/version'
require 'new_relic/infinite_tracing/config'

DependencyDetection.defer do
  named :infinite_tracing

  depends_on do
    NewRelic::Agent::InfiniteTracing::Config.should_load?
  end

  executes do
    NewRelic::Agent.logger.debug "Loading New Relic Infinite Tracing Library"

    require 'new_relic/infinite_tracing/proto'

    require 'new_relic/infinite_tracing/constants'
    require 'new_relic/infinite_tracing/worker'
    require 'new_relic/infinite_tracing/record_status_handler'

    require 'new_relic/infinite_tracing/transformer'
    require 'new_relic/infinite_tracing/streaming_buffer'
    require 'new_relic/infinite_tracing/suspended_streaming_buffer'
    require 'new_relic/infinite_tracing/channel'
    require 'new_relic/infinite_tracing/connection'
    require 'new_relic/infinite_tracing/client'

    require 'new_relic/infinite_tracing/agent_integrations'
  end
end