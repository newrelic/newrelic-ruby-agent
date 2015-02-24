# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# NOTE there are multiple implementations of the MemCache client in Ruby,
# each with slightly different API's and semantics.
# See:
#     http://www.deveiate.org/code/Ruby-MemCache/ (Gem: Ruby-MemCache)
#     http://seattlerb.rubyforge.org/memcache-client/ (Gem: memcache-client)
#     http://github.com/mperham/dalli (Gem: dalli)

require 'new_relic/agent/datastores/metric_helper'

module NewRelic
  module Agent
    module Instrumentation
      module Memcache
        module_function

        METHODS = [:get, :get_multi, :set, :add, :incr, :decr, :delete, :replace, :append,
                   :prepend, :cas, :single_get, :multi_get, :single_cas, :multi_cas]

        def supported_methods_for(client_class)
          METHODS.select do |method_name|
            client_class.method_defined?(method_name) || client_class.private_method_defined?(method_name)
          end
        end

        def instrument_methods(client_class, supported_methods = nil)
          supported_methods ||= supported_methods_for(client_class)
          supported_methods.each do |method_name|

            visibility = NewRelic::Helper.instance_method_visibility client_class, method_name
            method_name_without = :"#{method_name}_without_newrelic_trace"

            client_class.class_eval do
              alias_method method_name_without, method_name

              define_method method_name do |*args, &block|
                metrics = Datastores::MetricHelper.metrics_for("Memcache", method_name)

                NewRelic::Agent::MethodTracer.trace_execution_scoped(metrics) do
                  t0 = Time.now
                  begin
                    send method_name_without, *args, &block
                  ensure
                    if NewRelic::Agent.config[:capture_memcache_keys]
                      NewRelic::Agent.instance.transaction_sampler.notice_nosql(args.first.inspect, (Time.now - t0).to_f) rescue nil
                    end
                  end
                end
              end

              send visibility, method_name
              send visibility, method_name_without
            end
          end
        end

      end
    end
  end
end

DependencyDetection.defer do
  @name = :memcache

  depends_on do
    !NewRelic::Agent.config[:disable_memcache_instrumentation]
  end

  depends_on do
    defined?(::MemCache) ||
      defined?(::Memcached) ||
      defined?(::Dalli::Client)
  end

  executes do
    if defined? ::MemCache
      ::NewRelic::Agent.logger.info 'Installing MemCache instrumentation'
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::MemCache)
    end

    if defined? ::Memcached
      ::NewRelic::Agent.logger.info 'Installing Memcached instrumentation'
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Memcached)
    end

    if defined? ::Dalli::Client
      ::NewRelic::Agent.logger.info 'Installing Dalli Memcache instrumentation'
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client)
    end
  end
end

DependencyDetection.defer do
  named :dalli_cas_client

  depends_on do
    !::NewRelic::Agent.config[:disable_memcache_instrumentation]
  end

  depends_on do
    # These CAS client methods are only optionally defined if users require
    # dalli/cas/client. Use a separate dependency block so it can potentially
    # re-evaluate after they've done that require.
    defined?(::Dalli::Client) &&
      ::Dalli::Client.instance_methods.include?(:get_cas)
  end

  CAS_CLIENT_METHODS = [:get_cas, :get_multi_cas, :set_cas, :replace_cas,
                        :delete_cas]

  executes do
    ::NewRelic::Agent.logger.info 'Installing Dalli CAS Client Memcache instrumentation'
    ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client,
                                                                    CAS_CLIENT_METHODS)
  end
end
