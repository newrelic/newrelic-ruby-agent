# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module GRPC
        module Helper
          def cleaned_method(method)
            method = method.to_s unless method.is_a?(String)
            return method unless method.start_with?('/')

            method[1..-1]
          end

          def host_denylisted?(host)
            NewRelic::Agent.config[:'instrumentation.grpc.host_denylist'].any? do |regex|
              host.match?(regex)
            end
          end
        end
      end
    end
  end
end
