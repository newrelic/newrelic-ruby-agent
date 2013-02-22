# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :unicorn

  depends_on do
    defined?(::Unicorn) && defined?(::Unicorn::HttpServer)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Unicorn instrumentation'
    ::NewRelic::Agent.logger.info 'Detected Unicorn, please see additional documentation: https://newrelic.com/docs/troubleshooting/im-using-unicorn-and-i-dont-see-any-data'
  end

  executes do
    Unicorn::HttpServer.class_eval do
      old_worker_loop = instance_method(:worker_loop)
      define_method(:worker_loop) do |worker|
        NewRelic::Agent.after_fork(:force_reconnect => true)
        old_worker_loop.bind(self).call(worker)
      end
    end
  end
end
