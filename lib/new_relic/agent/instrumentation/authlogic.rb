DependencyDetection.defer do
  depends_on do
    defined?(AuthLogic) &&
      defined?(AuthLogic::Session) &&
      defined?(AuthLogic::Session::Base)
  end

  executes_on(:'AuthLogic::Session::Base') do
    add_method_tracer :find, 'Custom/Authlogic/find'
  end
end
