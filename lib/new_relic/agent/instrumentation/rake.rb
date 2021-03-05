# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'rake/rake_instrumentation'
require_relative 'rake/chain'

DependencyDetection.defer do
  # Why not :rake? newrelic-rake used that name, so avoid conflicting
  named :rake_instrumentation

  depends_on do
    defined?(::Rake) &&
      defined?(::Rake::VERSION) &&
      ::NewRelic::Agent.config[:'disable_rake'] == false &&
      ::NewRelic::Agent.config[:'rake.tasks'].any? &&
      ::NewRelic::Agent::Instrumentation::RakeInstrumentation.should_install?
  end

  executes do
    ::NewRelic::Agent.logger.info  "Installing Rake instrumentation"
    ::NewRelic::Agent.logger.debug "Instrumenting Rake tasks: #{::NewRelic::Agent.config[:'rake.tasks']}"
  end

  executes do
    chain_instrument NewRelic::Agent::Instrumentation::Rake::Chain
  end
end
