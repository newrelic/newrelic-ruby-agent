# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/configuration/manager'

module NewRelic::Agent
  class ErrorFilter
    class ErrorFilterTest < Minitest::Test

      # TODO: setup - read ignored/expected errors from config

      # TODO: test - parses error_collector.ignore_classes as Array; i.e.
      # - use test config that sets error_collector.ignore_classes = ['TestExceptionA', 'TestExceptionB']
      # - initialize error_filter object from config
      # - assert error_filter.for_class('TestExceptionA') == :ignore
      # - assert error_filter.for_class('TextExceptionC') == nil

      # TODO: test - parses error_collector.ignore_messages as Hash
      # - as above: error_collector.ignore_messages = {
      #               'TextExceptionA' => ['message one', 'message two']
      #             }
      # - assert error_filter.for_class('TestExceptionA', 'error message one test') == :ignore
      # - assert error_filter.for_class('TestExceptionA', 'error message three test') == nil

      # TODO: test - parses error_collector.ignore_status_codes as String
      # - as above: error_collector.ignore_status_codes = "404,507-511"
      # - assert error_filter.for_status('404') == :ignore
      # - assert error_filter.for_status('509') == :ignore
      # - assert error_filter.for_status('500') == nil

      # TODO: test - parses error_collector.ignore_errors as error_collector.ignored_classes
      #       (compatibility for deprecated config setting; split classes by ',' and store as ignore_classes)

      # TODO: test - parses error_collector.expected_classes as Array
      # TODO: test - parses error_collector.expected_messages as Hash
      # TODO: test - parses error_collector.expected_status_codes as String
    end
  end
end