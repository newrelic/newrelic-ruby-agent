# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# define special constant so DefaultSource.framework can return :test
module NewRelic; TEST = true; end unless defined? NewRelic::TEST

ENV['RAILS_ENV'] = 'test'

agent_test_path = File.expand_path('../../../test', __FILE__)
$LOAD_PATH << agent_test_path

require 'rubygems'
require 'rake'

require 'minitest/autorun'
require 'mocha/setup'

require 'newrelic_rpm'
require 'infinite_tracing'

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper

# Activates Infinite Tracing so we can test
DependencyDetection.detect!

# Load the agent's test helpers for use in infinite tracing tests
agent_helper_path = File.join(agent_test_path, 'helpers')
require File.join(agent_helper_path, 'file_searching.rb')
require File.join(agent_helper_path, 'config_scanning.rb')
require File.join(agent_helper_path, 'misc.rb')
require File.join(agent_helper_path, 'logging.rb')
require File.join(agent_helper_path, 'exceptions.rb')

Dir[File.expand_path('../support/*', __FILE__)].each { |f| require f }

def timeout_cap duration=1.0
  Timeout::timeout(duration) { yield }
rescue Timeout::Error => error
  raise Timeout::Error, "Unexpected timeout occurred after #{duration} seconds. #{error.backtrace.reject{|r| r =~ /gems\/minitest/}.join("\n")}"
end

def deferred_span segment
  Proc.new { NewRelic::Agent::SpanEventPrimitive.for_segment(segment) }
end

def reset_infinite_tracer
  ::NewRelic::Agent.instance.instance_variable_set(:@infinite_tracer, nil)
end

CLIENT_MUTEX = Mutex.new

# Prevent parallel runs against the client in this test suite
def with_serial_lock
  timeout_cap(15) do
    CLIENT_MUTEX.synchronize { yield }
  end
end

TRACE_POINT_ENABLED = false

def trace 
  @trace ||= TracePoint.new(:call, :b_call) do |tp|
    next unless tp.defined_class.to_s =~ /InfiniteTracing/
    next unless [
      :record_spans, 
      :record_span, 
      :emulate_streaming_with_ok_close_response,
      :handle_error,
      :handle_close,
      :notice_span,
      :transfer_buffer,
      :start,
      :stop,
      :rpc,
      :start_streaming,
      :notice_span,
      :wait_for_notice,
    ].include? tp.method_id
    p [tp.lineno, tp.defined_class, tp.method_id, tp.event]
  end
end

def with_detailed_trace
  if TRACE_POINT_ENABLED
    trace.enable { yield }
  else
    yield
  end
end



