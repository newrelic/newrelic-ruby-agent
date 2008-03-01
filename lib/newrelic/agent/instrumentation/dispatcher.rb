require 'dispatcher'

# NewRelic RPM instrumentation for http request dispatching (Routes mapping)
# Note, the dispatcher class from no module into into the ActionController modile 
# in rails 2.0.  Thus we need to check for both
if defined? ActionController::Dispatcher

  class ActionController::Dispatcher
    class << self
      add_method_tracer :dispatch, 'Rails/HTTP Dispatch', false
    end
  end
  
elsif defined? Dispatcher

  class Dispatcher
    class << self
      add_method_tracer :dispatch, 'Rails/HTTP Dispatch', false
    end
  end

end