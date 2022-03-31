# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# class to handle the responses to the client from the server
module NewRelic
  module Agent
    module InfiniteTracing
      class ServerResponseSimulator
        def initialize
          @buffer = Queue.new
        end

        def << value
          @buffer << value
        end

        def empty?
          @buffer.empty?
        end

        def enumerator
          return enum_for(:enumerator) unless block_given?
          loop do
            if return_value = @buffer.pop(false)
              # grpc raises any errors it gets rather than yielding them, this mimics that behavior
              if return_value.is_a?(GRPC::BadStatus) && !return_value.is_a?(GRPC::Ok)
                raise return_value
              end
              yield return_value
            end
          end
        end
      end
    end
  end
end
