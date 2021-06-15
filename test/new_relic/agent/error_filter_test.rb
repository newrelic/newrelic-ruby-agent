# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class TestExceptionA < StandardError; end
class TestExceptionB < StandardError; end

module NewRelic::Agent
  class ErrorFilter
    class ErrorFilterTest < Minitest::Test

      def setup
        @error_filter = NewRelic::Agent::ErrorFilter.new
      end

      def test_ignore_classes
        with_config :'error_collector.ignore_classes' => ['TestExceptionA', 'TestExceptionC'] do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new)
          refute @error_filter.ignore?(TestExceptionB.new)
        end
      end

      def test_ignore_messages
        with_config :'error_collector.ignore_messages' => {'TestExceptionA' => ['message one', 'message two']} do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new('message one'))
          assert @error_filter.ignore?(TestExceptionA.new('message two'))
          refute @error_filter.ignore?(TestExceptionA.new('message three'))
          refute @error_filter.ignore?(TestExceptionB.new('message one'))
        end
      end

      # TODO: test - parses error_collector.ignore_status_codes as String
      # - as above: error_collector.ignore_status_codes = "404,507-511"
      # - assert error_filter.for_status('404') == :ignore
      # - assert error_filter.for_status('509') == :ignore
      # - assert error_filter.for_status('500') == nil

      # compatibility for deprecated config setting
      def test_ignore_errors
        with_config :'error_collector.ignore_errors' => 'TestExceptionA,TestExceptionC' do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new)
          refute @error_filter.ignore?(TestExceptionB.new)
        end
      end

      def test_expected_classes
        with_config :'error_collector.expected_classes' => ['TestExceptionA', 'TestExceptionC'] do
          @error_filter.load_all
          assert @error_filter.expected?(TestExceptionA.new)
          refute @error_filter.expected?(TestExceptionB.new)
        end
      end

      def test_expected_messages
        with_config :'error_collector.expected_messages' => {'TestExceptionA' => ['message one', 'message two']} do
          @error_filter.load_all
          assert @error_filter.expected?(TestExceptionA.new('message one'))
          assert @error_filter.expected?(TestExceptionA.new('message two'))
          refute @error_filter.expected?(TestExceptionA.new('message three'))
          refute @error_filter.expected?(TestExceptionB.new('message one'))
        end
      end

      # TODO: test - parses error_collector.expected_status_codes as String
    end
  end
end