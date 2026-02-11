# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'tasks/newrelic'

class WhichIsWhich
  include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
  include ::NewRelic::Agent::MethodTracer

  def self.samename
    APP_TRACER.in_span('WhichIsWhich.samename', kind: :consumer) do
      'Class (static) method named samename'
    end
  end

  class << self
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include ::NewRelic::Agent::MethodTracer
    add_transaction_tracer :samename, category: :task if !NewRelic::Agent.config[:'opentelemetry.enabled']
  end

  def samename
    span = APP_TRACER.start_span('WhichIsWhich#samename', kind: :consumer)
    'Instance method named samename'
    span&.finish
  end
  add_transaction_tracer :samename, category: :task if !NewRelic::Agent.config[:'opentelemetry.enabled']
end
