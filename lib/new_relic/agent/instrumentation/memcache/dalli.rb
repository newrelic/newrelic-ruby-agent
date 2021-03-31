# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Memcache
        module DalliCAS
          extend Helper
          module_function

          def should_instrument?
            supported_methods_for(::Dalli::Client, dalli_cas_methods).any?
          end

          def instrument!
            instrument_methods ::Dalli::Client, dalli_cas_methods
            instrument_multi_method :get_multi_cas
          end
        end

        module Dalli
          extend Helper
          module_function

          def instrument!
            if supports_datastore_instances?
              instrument_methods(::Dalli::Client, dalli_methods)
              instrument_multi_method :get_multi
              instrument_send_multiget
              instrument_server_for_key
            else
              instrument_methods(::Dalli::Client, client_methods)
            end
          end

          def instrument_server_for_key
            ::Dalli::Ring.class_eval do
              include NewRelic::Agent::Instrumentation::Memcache::Tracer

              alias_method :server_for_key_without_newrelic_trace, :server_for_key

              def server_for_key key
                server_for_key_with_newrelic_tracing { server_for_key_without_newrelic_trace key }
              end
            end
          end

          def instrument_send_multiget
            ::Dalli::Server.class_eval do
              include NewRelic::Agent::Instrumentation::Memcache::Tracer
              alias_method :send_multiget_without_newrelic_trace, :send_multiget

              def send_multiget keys
                send_multiget_with_newrelic_tracing(keys) { send_multiget_without_newrelic_trace keys }
              end
            end
          end

        end
      end
    end
  end
end

