# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/control/instrumentation'

class InstrumentationTestClass
  include NewRelic::Control::Instrumentation
end

class NewRelic::Control::InstrumentationTest < Minitest::Test
  def setup
    @test_class = InstrumentationTestClass.new
  end

  def test_load_instrumentation_files_logs_errors_during_require
    swap_instance_method(Object, :require, Proc.new { |_| raise 'Instrumentation Test Error' }) do
      NewRelic::Agent.logger.expects(:warn).at_least_once.with() { |msg| msg.match(/Error loading/) }
      @test_class.load_instrumentation_files '*'
    end
  end
end
