# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# NOTE there are multiple implementations of the MemCache client in Ruby,
# each with slightly different API's and semantics.
# See:
#     http://www.deveiate.org/code/Ruby-MemCache/ (Gem: Ruby-MemCache)
#     http://seattlerb.rubyforge.org/memcache-client/ (Gem: memcache-client)
#     http://github.com/mperham/dalli (Gem: dalli)

module NewRelic
  module Agent
    module Instrumentation
      module Memcache
        module_function
        def instrument_methods(the_class, method_names)
          method_names.each do |method_name|
            next unless the_class.method_defined?(method_name.to_sym) || the_class.private_method_defined?(method_name.to_sym)
            visibility = "private" unless the_class.method_defined?(method_name.to_sym)
            the_class.class_eval <<-EOD
              #{visibility}
              def #{method_name}_with_newrelic_trace(*args, &block)
                metrics = ["Memcache/#{method_name}",
                           (NewRelic::Agent::Transaction.recording_web_transaction? ? 'Memcache/allWeb' : 'Memcache/allOther')]
                self.class.trace_execution_scoped(metrics) do
                  t0 = Time.now
                  begin
                    #{method_name}_without_newrelic_trace(*args, &block)
                  ensure
                    #{memcache_key_snippet(method_name)}
                  end
                end
              end
              alias #{method_name}_without_newrelic_trace #{method_name}
              alias #{method_name} #{method_name}_with_newrelic_trace
            EOD
         end
        end
        def memcache_key_snippet(method_name)
          return "" unless NewRelic::Agent.config[:capture_memcache_keys]
          "NewRelic::Agent.instance.transaction_sampler.notice_nosql(args.first.inspect, (Time.now - t0).to_f) rescue nil"
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
    defined?(::MemCache) || defined?(::Memcached) ||
      defined?(::Dalli::Client) || defined?(::Spymemcached)
  end

  executes do
    commands = %w[get get_multi set add incr decr delete replace append prepend]
    if defined? ::MemCache
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::MemCache,
                                                                    commands)
      ::NewRelic::Agent.logger.info 'Installing MemCache instrumentation'
    end
    if defined? ::Memcached
      if ::Memcached::VERSION >= '1.8.0'
        commands -= %w[get get_multi]
        commands += %w[single_get multi_get single_cas multi_cas]
      else
        commands << 'cas'
      end
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Memcached,
                                                                    commands)
      ::NewRelic::Agent.logger.info 'Installing Memcached instrumentation'
    end
    if defined? ::Dalli::Client
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Dalli::Client,
                                                                    commands)
      ::NewRelic::Agent.logger.info 'Installing Dalli Memcache instrumentation'
    end
    if defined? ::Spymemcached
      commands << 'multiget'
      NewRelic::Agent::Instrumentation::Memcache.instrument_methods(::Spymemcached,
                                                                    commands)
      ::NewRelic::Agent.logger.info 'Installing Spymemcached instrumentation'
    end
  end
end
