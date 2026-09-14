# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Reuses DependencyDetection's machinery to gate our own feature on stackprof/google-protobuf,
# not to instrument a third-party library.

DependencyDetection.defer do
  # Set directly, not via +named+ -- the orphan-config test treats +named+ as a promise that
  # +disable_<name>+/+instrumentation.<name>+ exist, and profiling.enabled is the real toggle.
  @name = :continuous_profiler

  depends_on do
    defined?(StackProf) &&
      defined?(Google::Protobuf) &&
      NewRelic::Agent.config[:'profiling.enabled'] &&
      !NewRelic::LanguageSupport.jruby?
  end

  executes do
    NewRelic::Agent.logger.info('Starting continuous profiling session')
    NewRelic::Agent.agent.continuous_profiling_session.maybe_start
  end
end
