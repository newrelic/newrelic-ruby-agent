# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'uri'

require 'newrelic_rpm'

NewRelic::Agent.logger.debug "Detected New Relic Infinite Tracing Gem"

require 'infinite_tracing/version'
require 'infinite_tracing/config'

DependencyDetection.defer do
  named :infinite_tracing

  depends_on do
    NewRelic::Agent::InfiniteTracing::Config.should_load?
  end

  executes do
    NewRelic::Agent.logger.debug "Loading New Relic Infinite Tracing Libary"

    require 'infinite_tracing/proto'

    require 'infinite_tracing/constants'
    require 'infinite_tracing/worker'
    require 'infinite_tracing/record_status_handler'

    require 'infinite_tracing/transformer'
    require 'infinite_tracing/streaming_buffer'
    require 'infinite_tracing/suspended_streaming_buffer'
    require 'infinite_tracing/channel'
    require 'infinite_tracing/connection'
    require 'infinite_tracing/client'

    require 'infinite_tracing/agent_integrations'
  end
end