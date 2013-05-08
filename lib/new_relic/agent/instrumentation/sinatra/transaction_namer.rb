# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Sinatra
        module TransactionNamer
          extend self

          def transaction_name_for_route(route, request)
            transaction_name(route.source, request)
          end

          def initial_transaction_name(request)
            transaction_name(::NewRelic::Agent::UNKNOWN_METRIC, request)
          end

          def transaction_name(route_text, request)
            verb = http_verb(request)

            name = route_text.gsub(%r{^[/^\\A]*(.*?)[/\$\?\\z]*$}, '\1')
            name = "#{verb} #{name}" unless verb.nil?
            name
          rescue => e
            ::NewRelic::Agent.logger.debug("#{e.class} : #{e.message} - Error encountered trying to identify Sinatra transaction name")
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
