# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :rubyprof

  depends_on do
    defined?(::RubyProf)
  end

  executes do
    NewRelic::Agent.instance.events.subscribe(:start_transaction) do
      if NewRelic::Agent.config[:'profiling.enabled']
        ::RubyProf.start
      end
    end

    NewRelic::Agent.instance.events.subscribe(:transaction_finished) do
      if NewRelic::Agent.config[:'profiling.enabled']
        trace = NewRelic::Agent::TransactionState.get.transaction.transaction_trace
        trace.profile = ::RubyProf.stop
      end
    end
  end
end
