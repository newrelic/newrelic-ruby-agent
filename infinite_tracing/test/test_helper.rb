# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
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
require 'new_relic/infinite_tracing'

agent_helper_path = File.join(agent_test_path, 'helpers')
require File.join(agent_helper_path, 'file_searching.rb')
require File.join(agent_helper_path, 'config_scanning.rb')
require File.join(agent_helper_path, 'misc.rb')

Dir[File.expand_path('../support/*', __FILE__)].each { |f| require f }

require File.expand_path(File.join(File.dirname(__FILE__), '..',  '..', 'test', 'helpers', 'exceptions'))

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper

def timeout_cap duration=3
  Timeout::timeout(duration) { yield }
rescue Timeout::Error => error
  refute true, "Unexpected timeout occurred after #{duration} seconds. #{error.backtrace.reject{|r| r =~ /gems\/minitest/}.join("\n")}"
end

def deferred_span segment
  Proc.new { NewRelic::Agent::SpanEventPrimitive.for_segment(segment) }
end

def reset_infinite_tracer
  ::NewRelic::Agent.instance.instance_variable_set(:@infinite_tracer, nil)
end


