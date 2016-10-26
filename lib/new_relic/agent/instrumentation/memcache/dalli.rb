# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/memcache'

module NewRelic
  module Agent
    module Instrumentation
      module Memcache
        module Dalli
          extend self

          METHODS = [:get, :set, :add, :incr, :decr, :delete, :replace, :append, :prepend, :cas]
          MULTI_METHODS = [:get_multi]

          def instrument_methods
            ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client, METHODS + MULTI_METHODS)
            # instrument_server_for_key
          end

          def instrument_server_for_key
            ::Dalli::Client.class_eval do
            end
          end

        end
      end
    end
  end
end

DependencyDetection.defer do
  named :dalli

  depends_on do
    NewRelic::Agent::Instrumentation::Memcache.enabled?
  end

  depends_on do
    defined?(::Dalli::Client)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Memcache instrumentation for dalli gem'
    ::NewRelic::Agent::Instrumentation::Memcache::Dalli.instrument_methods
  end
end

DependencyDetection.defer do
  named :dalli_cas_client

  depends_on do
    NewRelic::Agent::Instrumentation::Memcache.enabled?
  end

  depends_on do
    # These CAS client methods are only optionally defined if users require
    # dalli/cas/client. Use a separate dependency block so it can potentially
    # re-evaluate after they've done that require.
    defined?(::Dalli::Client) &&
      ::NewRelic::Agent::Instrumentation::Memcache.supported_methods_for(::Dalli::Client,
                                                                         CAS_CLIENT_METHODS).any?
  end

  CAS_CLIENT_METHODS = [:get_cas, :get_multi_cas, :set_cas, :replace_cas,
                        :delete_cas]

  executes do
    ::NewRelic::Agent.logger.info 'Installing Dalli CAS Client Memcache instrumentation'
    ::NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client,
                                                                    CAS_CLIENT_METHODS)
  end
end
