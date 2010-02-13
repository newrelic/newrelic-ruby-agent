# NOTE there are multiple implementations of the MemCache client in Ruby,
# each with slightly different API's and semantics.  
# See:
#     http://www.deveiate.org/code/Ruby-MemCache/ (Gem: Ruby-MemCache)
#     http://seattlerb.rubyforge.org/memcache-client/ (Gem: memcache-client)
unless NewRelic::Control.instance['disable_memcache_instrumentation']
  MemCache.class_eval do
    
    # This is in the memcache-client implementation and has never existed in Ruby-MemCache
    if self.method_defined? :cache_get

      if self.method_defined? :get
        def get_with_newrelic_trace(key, raw=false)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/read', 'MemCache/allWeb']) do
              get_without_newrelic_trace(key, raw)
            end
          else
            self.class.trace_execution_scoped(['MemCache/read', 'MemCache/allOther']) do
              get_without_newrelic_trace(key, raw)
            end
          end
        end
        
        alias get_without_newrelic_trace get
        alias get get_with_newrelic_trace
      end

      if self.method_defined? :get_multi
        def get_multi_with_newrelic_trace(*keys)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/read', 'MemCache/allWeb']) do
              get_without_newrelic_trace(keys)
            end
          else
            self.class.trace_execution_scoped(['MemCache/read', 'MemCache/allOther']) do
              get_without_newrelic_trace(keys)
            end
          end
        end
        
        alias get_multi_without_newrelic_trace get_multi
        alias get_multi get_multi_with_newrelic_trace
      end

      if self.method_defined? :add
        def add_with_newrelic_trace(key, value, expiry=0, raw=false)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allWeb']) do
              add_without_newrelic_trace(key, value, expiry, raw)
            end
          else
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allOther']) do
              add_without_newrelic_trace(key, value, expiry, raw)
            end
          end
        end
        
        alias add_without_newrelic_trace add
        alias add add_with_newrelic_trace
      end

      if self.method_defined? :decr
        def decr_with_newrelic_trace(key, amount=1)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allWeb']) do
              decr_without_newrelic_trace(key, amount)
            end
          else
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allOther']) do
              decr_without_newrelic_trace(key, amount)
            end
          end
        end

        alias decr_without_newrelic_trace decr
        alias decr decr_with_newrelic_trace
      end

      if self.method_defined? :delete
        def delete_with_newrelic_trace(key, expiry=0)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allWeb']) do
              delete_without_newrelic_trace(key, expiry)
            end
          else
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allOther']) do
              delete_without_newrelic_trace(key, expiry)
            end
          end
        end
        
        alias delete_without_newrelic_trace delete
        alias delete delete_with_newrelic_trace
      end

      if self.method_defined? :incr
        def incr_with_newrelic_trace(key, amount=1)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allWeb']) do
              incr_without_newrelic_trace(key, amount)
            end
          else
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allOther']) do
              incr_without_newrelic_trace(key, amount)
            end
          end
        end

        alias incr_without_newrelic_trace incr
        alias incr incr_with_newrelic_trace
      end

      if self.method_defined? :set
        def set_with_newrelic_trace(key, value, expiry=0, raw=false)
          if NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allWeb']) do
              set_without_newrelic_trace(key, value, expiry, raw)
            end
          else
            self.class.trace_execution_scoped(['MemCache/write', 'MemCache/allOther']) do
              set_without_newrelic_trace(key, value, expiry, raw)
            end
          end
        end
        
        alias set_without_newrelic_trace set
        alias set set_with_newrelic_trace
      end

    else  # Ruby-MemCache
      add_method_tracer :get, 'MemCache/read' if self.method_defined? :get
      add_method_tracer :get_multi, 'MemCache/read' if self.method_defined? :get_multi
      %w[set add incr decr delete].each do | method |
        add_method_tracer method, 'MemCache/write' if self.method_defined? method
      end
    end
  end if defined? MemCache 
  
  # Support for libmemcached through Evan Weaver's memcached wrapper
  # http://blog.evanweaver.com/files/doc/fauna/memcached/classes/Memcached.html    
  Memcached.class_eval do
    add_method_tracer :get, 'MemCache/read' if self.method_defined? :get
  %w[set add increment decrement delete replace append prepend cas].each do | method |
      add_method_tracer method, "MemCache/write" if self.method_defined? method
    end
  end if defined? Memcached

end
