# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Memcache
    module Helper

      MEMCACHED = "Memcached"
      SEND_MULTIGET_METRIC_NAME = "get_multi_request"
      DATASTORE_INSTANCES_SUPPORTED_VERSION = Gem::Version.new '2.6.4'
      SLASH = '/'
      UNKNOWN = 'unknown'
      LOCALHOST = 'localhost'

      def supports_datastore_instances?
        DATASTORE_INSTANCES_SUPPORTED_VERSION <= Gem::Version.new(::Dalli::VERSION)
      end

      def client_methods
        [:get, :get_multi, :set, :add, :incr, :decr, :delete, :replace, :append,
          :prepend, :cas, :single_get, :multi_get, :single_cas, :multi_cas]
      end

      def dalli_methods
        [:get, :set, :add, :incr, :decr, :delete, :replace, :append, :prepend, :cas]
      end

      def dalli_cas_methods
        [:get_cas, :set_cas, :replace_cas, :delete_cas]
      end

      def supported_methods_for(client_class, methods)
        methods.select do |method_name|
          client_class.method_defined?(method_name) || client_class.private_method_defined?(method_name)
        end
      end

      def instrument_methods(client_class, requested_methods = METHODS)
        supported_methods_for(client_class, requested_methods).each do |method_name|

          visibility = NewRelic::Helper.instance_method_visibility client_class, method_name
          method_name_without = :"#{method_name}_without_newrelic_trace"

          client_class.class_eval do
            include NewRelic::Agent::Instrumentation::Memcache::Tracer

            alias_method method_name_without, method_name

            define_method method_name do |*args, &block|
              with_newrelic_tracing(method_name, *args) { send method_name_without, *args, &block }
            end

            send visibility, method_name
            send visibility, method_name_without
          end
        end
      end

      def instrument_multi_method method_name
        visibility = NewRelic::Helper.instance_method_visibility ::Dalli::Client, method_name
        method_name_without = :"#{method_name}_without_newrelic_trace"

        ::Dalli::Client.class_eval do
          alias_method method_name_without, method_name

          define_method method_name do |*args, &block|
            segment = NewRelic::Agent::Tracer.start_segment name: "Ruby/Memcached/Dalli/#{method_name}"
            begin
              NewRelic::Agent::Tracer.capture_segment_error segment do                  
                __send__ method_name_without, *args, &block
              end
            ensure
              segment.finish if segment
            end
          end

          __send__ visibility, method_name
          __send__ visibility, method_name_without
        end
      end

      def assign_instance_to segment, server
        host = port_path_or_id = nil
        if server.hostname.start_with? SLASH
          host = LOCALHOST
          port_path_or_id = server.hostname
        else
          host = server.hostname
          port_path_or_id = server.port
        end
        segment.set_instance_info host, port_path_or_id
      rescue => e
        ::NewRelic::Agent.logger.debug "Failed to retrieve memcached instance info: #{e.message}"
        segment.set_instance_info UNKNOWN, UNKNOWN
      end
      module_function :assign_instance_to

    end
  end
end

