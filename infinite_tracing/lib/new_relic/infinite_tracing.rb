# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'newrelic_rpm'

module NewRelic
  module Agent
    module InfiniteTracing
    end
  end
end

require 'new_relic/infinite_tracing/version'
require 'new_relic/infinite_tracing/proto'

require 'new_relic/infinite_tracing/transformer'
require 'new_relic/infinite_tracing/streaming_buffer'