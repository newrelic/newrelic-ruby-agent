DependencyDetection.defer do
  @name = :rainbows

  depends_on do
    defined?(::Rainbows) && defined?(::Rainbows::HttpServer)
  end
  
  executes do
    NewRelic::Agent.logger.debug 'Installing Rainbows instrumentation'
  end
  
  executes do
    Rainbows::HttpServer.class_eval do
      old_worker_loop = instance_method(:worker_loop)
      define_method(:worker_loop) do | worker |
        NewRelic::Agent.after_fork(:force_reconnect => true)
        old_worker_loop.bind(self).call(worker)
      end
    end
  end
end
