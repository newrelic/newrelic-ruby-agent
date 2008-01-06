# NewRelic Agent instrumentation for miscellaneous parts of the rails platform

# instrumentation for dynamic application code loading (usually only happens a lot
# in developmetn environment)
module Dependencies
  add_method_tracer :load_file, "Rails/Application Code Loading"
end

# instrumentation for core rails dispatching
class Dispatcher
  class << self
    add_method_tracer :dispatch, 'Rails/HTTP Dispatch', false
  end
end

class ERB::Compiler
  add_method_tracer :compile, 'View/.rhtml Processing'
end


