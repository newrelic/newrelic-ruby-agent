require 'newrelic/agent/agent'
require 'newrelic/agent/method_tracer'
require 'newrelic/agent/session_tracer' if false # turn off for now until we get it working

require 'dispatcher'
require 'erb'

# set the log for method tracer instrumentation engine to be
# the NewRelic Agent's log
log = NewRelic::Agent.instance.log
Module.method_tracer_log = log

# Instrumentation for the key code points inside rails for monitoring by NewRelic.
# note this file is loaded only if the newrelic agent is enabled (through config/newrelic.yml)
instrumentation_files = File.join(File.dirname(__FILE__), 'instrumentation', '*.rb')
Dir.glob(instrumentation_files) do |file|
  begin
    require file
    log.info "Processed instrumentation file '#{file}'"
  rescue Exception => e
    log.error "Error loading instrumentation file '#{file}': #{e}"
  end
end


