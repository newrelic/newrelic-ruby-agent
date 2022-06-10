# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Client
          class ResponseWrapper
            def initialize(response)
              @wrapped_response = response
            end

            def [](key)
              # TODO: gRPC equivalent
              @wrapped_response[key]
            end
          end
        end
      end
    end
  end
end
