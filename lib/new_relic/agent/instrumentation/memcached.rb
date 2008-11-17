

# Support for libmemcached through Evan Weaver's memcached wrapper
# http://blog.evanweaver.com/files/doc/fauna/memcached/classes/Memcached.html    

Memcached.class_eval do
  add_method_tracer :get, 'Memcached/read'
  add_method_tracer :set, 'Memcached/write'
end if defined? Memcached
