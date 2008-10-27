# NewRelic Agent instrumentation for miscellaneous parts of the rails platform

# instrumentation for dynamic application code loading (usually only happens a lot
# in development environment)

class ERB::Compiler
  add_method_tracer :compile, 'View/.rhtml Processing'
end


