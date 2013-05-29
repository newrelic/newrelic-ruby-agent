# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/sinatra'

DependencyDetection.defer do
  @name = :padrino

  depends_on do
    !NewRelic::Agent.config[:disable_sinatra] &&
      defined?(::Padrino) && defined?(::Padrino::Routing::InstanceMethods)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Padrino instrumentation'

    # Our Padrino instrumentation relies heavily on the fact that Padrino is
    # built on Sinatra. Although it wires up a lot of its own routing logic,
    # we only need to patch into Padrino's dispatch to get things started.
    #
    # Parts of the Sinatra instrumentation (such as the TransactionNamer) are
    # aware of Padrino as a potential target in areas where both Sinatra and
    # Padrino run through the same code.
    module ::Padrino::Routing::InstanceMethods
      include NewRelic::Agent::Instrumentation::Sinatra

      alias dispatch_without_newrelic dispatch!
      alias dispatch! dispatch_with_newrelic
    end
  end
end
