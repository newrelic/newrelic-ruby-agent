# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'tasks/newrelic'

class WhichIsWhich
  include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
  include ::NewRelic::Agent::MethodTracer

  def self.samename
    'Class (static) method named samename'
  end

  class << self
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include ::NewRelic::Agent::MethodTracer
    add_transaction_tracer :samename, category: :task
  end

  def samename
    'Instance method named samename'
  end
  add_transaction_tracer :samename, category: :task
end
