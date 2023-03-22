# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'memcache/helper'
require_relative 'memcache/instrumentation'
require_relative 'memcache/dalli'
require_relative 'memcache/prepend'

DependencyDetection.defer do
  @name = :dalli
  configure_with :memcache

  depends_on { defined? Dalli::Client && defined? ::Dalli::VERSION && Gem::Version.new(::Dalli::VERSION) >= Gem::Version.new('3.2.1') }

  executes do
    if use_prepend?
      prepend_module = NewRelic::Agent::Instrumentation::Memcache::Prepend
      prepend_module.dalli_prependers do |client_class, instrumenting_module|
        prepend_instrument client_class, instrumenting_module, 'MemcachedDalli'
      end
    else
      chain_instrument NewRelic::Agent::Instrumentation::Memcache::Dalli
    end
  end
end

# These CAS client methods are only optionally defined if users require
# dalli/cas/client. Use a separate dependency block so it can potentially
# re-evaluate after they've done that require.
DependencyDetection.defer do
  @name = :dalli_cas_client
  configure_with :memcache

  depends_on { defined? Dalli::Client }
  depends_on { NewRelic::Agent::Instrumentation::Memcache::DalliCAS.should_instrument? }

  executes do
    NewRelic::Agent.logger.info('Installing Dalli CAS Client Memcache instrumentation')
    if use_prepend?
      prepend_module = NewRelic::Agent::Instrumentation::Memcache::Prepend
      prepend_module.dalli_cas_prependers do |client_class, instrumenting_module|
        prepend_instrument client_class, instrumenting_module, 'MemcachedDalliCAS'
      end
    else
      chain_instrument NewRelic::Agent::Instrumentation::Memcache::DalliCAS
    end
  end
end
