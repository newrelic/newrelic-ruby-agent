# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :authlogic

  depends_on do
    defined?(AuthLogic) &&
      defined?(AuthLogic::Session) &&
      defined?(AuthLogic::Session::Base)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing AuthLogic instrumentation'
  end

  executes do
    AuthLogic::Session::Base.class_eval do
      add_method_tracer :find, 'Custom/Authlogic/find'
    end
  end
end
