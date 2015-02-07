# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/deprecator'

class DeprecatorTest < Minitest::Test
  def setup
    @old_method = :foo
    @new_method = :bar
    @version = "3.11.0"
  end

  def teardown
    ::NewRelic::Agent.logger.clear_already_logged
  end

  def test_deprecator_logs_a_warning_with_the_name_of_the_method
    NewRelic::Agent.logger.expects(:warn).with do |messages|
      messages.first.include? @old_method.to_s
    end
    NewRelic::Agent::Deprecator.deprecate(@old_method)
  end

  def test_deprecator_logs_once
    NewRelic::Agent.logger.expects(:warn).with do |messages|
      messages.first.include? @old_method.to_s
    end
    NewRelic::Agent::Deprecator.deprecate(@old_method)
    NewRelic::Agent::Deprecator.deprecate(@old_method)
  end

  def test_deprecator_logs_the_new_method_if_given
    NewRelic::Agent.logger.expects(:warn).with do |messages|
      messages.last.include? @new_method.to_s
    end
    NewRelic::Agent::Deprecator.deprecate(@old_method, @new_method)
  end

  def test_deprecator_logs_the_version_if_given
    NewRelic::Agent.logger.expects(:warn).with do |messages|
      messages[1].include? @version.to_s
    end
    NewRelic::Agent::Deprecator.deprecate(@old_method, @new_method, @version)
  end

  def test_deprecator_reports_a_supportability_metric
    NewRelic::Agent::Deprecator.deprecate(:deprecated_supportability_test)
    assert_metrics_recorded("Supportability/Deprecated/deprecated_supportability_test")
  end
end
