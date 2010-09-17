# NOTE there are multiple implementations of the MemCache client in Ruby,
# each with slightly different API's and semantics.
# See:
#     http://www.deveiate.org/code/Ruby-MemCache/ (Gem: Ruby-MemCache)
#     http://seattlerb.rubyforge.org/memcache-client/ (Gem: memcache-client)
#     http://github.com/mperham/dalli (Gem: dalli)
unless NewRelic::Control.instance['disable_memcache_instrumentation']

  def self.instrument_method(the_class, method_name)
    return unless the_class.method_defined? method_name.to_sym
    the_class.class_eval <<-EOD
        def #{method_name}_with_newrelic_trace(*args)
          metrics = ["MemCache/#{method_name}",
                     (NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction? ? 'MemCache/allWeb' : 'MemCache/allOther')]
          self.class.trace_execution_scoped(metrics) do
            t0 = Time.now
            begin
              #{method_name}_without_newrelic_trace(*args)
            ensure
              #{memcache_key_snippet(method_name)}
            end
          end
        end
        alias #{method_name}_without_newrelic_trace #{method_name}
        alias #{method_name} #{method_name}_with_newrelic_trace
    EOD
      end

      def self.memcache_key_snippet(method_name)
        return "" unless NewRelic::Control.instance['capture_memcache_keys']
        "NewRelic::Agent.instance.transaction_sampler.notice_nosql(args.first.inspect, (Time.now - t0).to_f) rescue nil"
      end



  %w[get get_multi set add incr decr delete replace append prepend cas].each do | method_name |
    instrument_method(::MemCache, method_name) if defined? ::MemCache
    instrument_method(::Memcached, method_name) if defined? ::Memcached
    instrument_method(::Dalli::Client, method_name) if defined? ::Dalli::Client
  end

end
