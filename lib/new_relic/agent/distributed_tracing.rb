# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'distributed_tracing/api'

module NewRelic
  module Agent
    module DistributedTracing
      extend NewRelic::Agent::DistributedTracing::API
    end
  end
end