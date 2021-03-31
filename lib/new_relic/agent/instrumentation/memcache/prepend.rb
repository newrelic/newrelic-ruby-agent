# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Memcache
    # # Prepending the Dalli library has a strange behavior not manifested in any other 
    # # library we're auto-instrumenting.  For some reason, original Dalli classes start resolving
    # # their modules/classes to the ::NewRelic::Agent::Instrumentation::Dalli::<target> namespace.
    # # The class/module constants below allows Dalli to be prepended and still continue to 
    # # function as intended.
    # Dalli::Server = ::Dalli::Server
    # Dalli::Client = ::Dalli::Client
    # Dalli::Ring = ::Dalli::Ring
    
    module Prepend
      extend Helper
      module_function

      def client_prepender client_class
        for_methods client_class, supported_methods_for(client_class, client_methods)
      end

      def for_methods client_class, supported_methods
        Module.new do
          extend Helper
          include NewRelic::Agent::Instrumentation::Memcache::Tracer

          supported_methods.each do |method_name|
            define_method method_name do |*args, &block|
              with_newrelic_tracing(method_name, *args) { super(*args, &block) }
            end
          end
        end
      end

      def dalli_prependers
        yield ::Dalli::Client, dalli_client_prepender
        if supports_datastore_instances?
          yield ::Dalli::Server, dalli_server_prepender              
          yield ::Dalli::Ring, dalli_ring_prepender
        end
      end

      def dalli_client_prepender
        Module.new do
          extend Helper
          include NewRelic::Agent::Instrumentation::Memcache::Tracer

          supported_methods = supports_datastore_instances? ? dalli_methods : client_methods
          require 'pry'; binding.pry
          supported_methods.each do |method_name|
            define_method method_name do |*args, &block|
              with_newrelic_tracing(method_name, *args) { super(*args, &block) }
            end
          end
        end
      end

      def dalli_ring_prepender
        return unless supports_datastore_instances?
        Module.new do
          extend Helper
          include NewRelic::Agent::Instrumentation::Memcache::Tracer

          def server_for_key key
            server_for_key_with_newrelic_tracing { super }
          end
        end
      end

      def dalli_server_prepender
        return unless supports_datastore_instances?
        Module.new do
          extend Helper
          include NewRelic::Agent::Instrumentation::Memcache::Tracer

          def send_multiget keys
            send_multiget_with_newrelic_tracing(keys) { super keys }
          end
        end
      end

    end
  end
end