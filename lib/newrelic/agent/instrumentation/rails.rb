# NewRelic Agent instrumentation for miscellaneous parts of the rails platform

# instrumentation for dynamic application code loading (usually only happens a lot
# in development environment)

# Rails Edge
if defined? ActiveSupport::Dependencies
  module ActiveSupport::Dependencies
    add_method_tracer :load_file, "Rails/Application Code Loading"
  end
else
  module Dependencies
    add_method_tracer :load_file, "Rails/Application Code Loading"
  end
end

class ERB::Compiler
  add_method_tracer :compile, 'View/.rhtml Processing'
end


