# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :rubyprof

  depends_on do
    defined?(::RubyProf) && defined?(::NewRelic::Rack::DeveloperMode) && ::NewRelic::Agent.config[:developer_mode]
  end

  executes do
    NewRelic::Agent.instance.events.subscribe(:start_transaction) do
      if NewRelic::Rack::DeveloperMode.profiling_enabled?
        ::RubyProf.start
      end
    end

    NewRelic::Agent.instance.events.subscribe(:transaction_finished) do
      if NewRelic::Rack::DeveloperMode.profiling_enabled?
        trace = NewRelic::Agent::Transaction.tl_current.transaction_trace
        trace.profile = ::RubyProf.stop
      end
    end
  end
end
