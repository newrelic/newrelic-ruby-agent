# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveStorageSubscriber < EventedSubscriber
        def start(name, id, payload)
          NewRelic::Agent.logger.debug "ActiveStorageSubscriber#start: name: #{name}, id: #{id}, payload: #{payload}"
        end

        def finish(name, id, payload)
          NewRelic::Agent.logger.debug "ActiveStorageSubscriber#finish: name: #{name}, id: #{id}, payload: #{payload}"
        end
      end
    end
  end
end
