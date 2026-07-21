# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Continuous profiling is not "instrumentation" for a third-party library in the
# traditional DependencyDetection sense. It gates New Relic's own continuous profiling
# feature on the customer having manually added two optional gems (stackprof,
# google-protobuf) to their own Gemfile. This unusual but intentional use of
# DependencyDetection reuses the existing detection, logging, and error-isolation
# machinery instead of hand-rolling equivalents.

DependencyDetection.defer do
  # Set +@name+ directly, as +puma+/+sequel+ do, rather than calling +named+. The two
  # are equivalent at runtime, but the orphan-config test treats a +named+ entry as a
  # promise that +disable_<name>+ / +instrumentation.<name>+ config keys exist. Those
  # keys carry chain/prepend instrumentation semantics that don't apply here, and
  # continuous_profiler.enabled below is already the real, non-redundant toggle.
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
