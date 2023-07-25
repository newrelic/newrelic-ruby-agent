# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Roda
        module TransactionNamer
          extend self

          def initial_transaction_name(request)
            transaction_name(::NewRelic::Agent::UNKNOWN_METRIC, request)
          end

          ROOT = '/'.freeze

          def transaction_name(path, request)
            verb = http_verb(request)
            path = request.path if request.path
            name = path.gsub(%r{^[/^\\A]*(.*?)[/\$\?\\z]*$}, '\1') # remove any rouge slashes
            name = ROOT if name.empty?
            name = "#{verb} #{name}" unless verb.nil?

            name
          rescue => e
            ::NewRelic::Agent.logger.debug("#{e.class} : #{e.message} - Error encountered trying to identify Roda transaction name")
            ::NewRelic::Agent::UNKNOWN_METRIC
          end

          def http_verb(request)
            request.request_method if request.respond_to?(:request_method)
          end
        end
      end
    end
  end
end
