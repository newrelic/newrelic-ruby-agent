# NOTE there are multiple implementations of the MemCache client in Ruby,
# each with slightly different API's and semantics.  
# Currently we only cover memcache-client.  Need to cover Ruby-MemCache.
# See:
#     http://www.deveiate.org/code/Ruby-MemCache/ (Gem: Ruby-MemCache)
#     http://dev.robotcoop.com/Libraries/memcache-client/ (Gem: memcache-client)
MemCache.class_eval do
  add_method_tracer :get, 'MemCache/read' if self.method_defined? :get  
  add_method_tracer :set, 'MemCache/write' if self.method_defined? :set
  add_method_tracer :get_multi, 'MemCache/read' if self.method_defined? :get_multi
end if defined? MemCache

# Support for libmemcached through Evan Weaver's memcached wrapper
# http://blog.evanweaver.com/files/doc/fauna/memcached/classes/Memcached.html    
Memcached.class_eval do
  add_method_tracer :get, 'Memcached/read' if self.method_defined? :get
  add_method_tracer :set, 'Memcached/write' if self.method_defined? :set
end if defined? Memcached
