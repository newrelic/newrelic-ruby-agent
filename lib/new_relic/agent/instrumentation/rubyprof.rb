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

    NewRelic::Agent.instance.events.subscribe(:transaction_finishing) do
      if NewRelic::Agent.config[:'profiling.enabled']
        profile = ::RubyProf.stop
        NewRelic::Agent.instance.transaction_sampler.notice_profile(profile)
      end
    end
  end
end
