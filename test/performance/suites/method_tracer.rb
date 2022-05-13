# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/method_tracer'

class KnockKnock
  def self.whos_there(guest)
    "#{guest} who?"
  end
end

class MethodTracerTest < Performance::TestCase
  include NewRelic::Agent::MethodTracer
  METHOD_TRACERS = [:tracer, :with_metric, :with_proc, :push_scope_false, :metric_false]

  # Helper Methods
  def tracer
    KnockKnock.class_eval { class << self; add_method_tracer :whos_there; end }
  end

  def with_metric
    KnockKnock.class_eval do
      class << self
        add_method_tracer :whos_there, 'Custom/KnockKnock/whos_there'
      end
    end
  end

  def with_proc
    KnockKnock.class_eval do
      class << self
        add_method_tracer :whos_there, -> { "Custom/#{self.name}/whos_there" }
      end
    end
  end

  def push_scope_false
    KnockKnock.class_eval do
      class << self
        add_method_tracer :whos_there, 'Custom/whos_there', push_scope: false
      end
    end
  end

  def metric_false
    KnockKnock.class_eval do
      class << self
        add_method_tracer :whos_there, 'Custom/whos_there', metric: false
      end
    end
  end

  # Tests
  METHOD_TRACERS.each do |method_tracer|
    define_method("test_#{method_tracer}_code_level_metrics_enabled") do
      measure do
        with_config(:'code_level_metrics.enabled' => true) do
          KnockKnock.whos_there('Guess')
        end
      end
    end

    define_method("test_#{method_tracer}_code_level_metrics_disabled") do
      measure do
        with_config(:'code_level_metrics.enabled' => false) do
          KnockKnock.whos_there('Guess')
        end
      end
    end
  end
end
