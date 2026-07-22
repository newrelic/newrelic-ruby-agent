# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Not "instrumentation" for a third-party library in the traditional DependencyDetection
# sense -- gates New Relic's own continuous profiling feature on the customer having
# added two optional gems (stackprof, google-protobuf) to their own Gemfile. Reuses
# DependencyDetection's detection/logging/error-isolation machinery rather than
# hand-rolling equivalents.

DependencyDetection.defer do
  # Set +@name+ directly, as +puma+/+sequel+ do, rather than calling +named+: the
  # orphan-config test treats +named+ as a promise that +disable_<name>+/
  # +instrumentation.<name>+ config keys exist, and those carry chain/prepend semantics
  # that don't apply here (continuous_profiler.enabled below is the real toggle).
  @name = :continuous_profiler

  depends_on do
    defined?(StackProf) &&
      defined?(Google::Protobuf) &&
      NewRelic::Agent.config[:'continuous_profiler.enabled'] &&
      !NewRelic::LanguageSupport.jruby?
  end

  executes do
    NewRelic::Agent.logger.info('Starting continuous profiling session')
    NewRelic::Agent.agent.continuous_profiling_session.maybe_start
  end
end
