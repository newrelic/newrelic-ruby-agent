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
          @error_filter.reload
          assert_equal :ignored, @error_filter.type_for_exception(TestExceptionA.new)
          assert_nil @error_filter.type_for_exception(TestExceptionB.new)
        end
      end

      def test_ignore_messages
        with_config :'error_collector.ignore_messages' => {'TestExceptionA' => ['message one', 'message two']} do
          @error_filter.reload
          assert_equal :ignored, @error_filter.type_for_exception(TestExceptionA.new('message one'))
          assert_equal :ignored, @error_filter.type_for_exception(TestExceptionA.new('message two'))
          assert_nil @error_filter.type_for_exception(TestExceptionA.new('message three'))
          assert_nil @error_filter.type_for_exception(TestExceptionB.new('message one'))
        end
      end

      # TODO: test - parses error_collector.ignore_status_codes as String
      # - as above: error_collector.ignore_status_codes = "404,507-511"
      # - assert error_filter.for_status('404') == :ignore
      # - assert error_filter.for_status('509') == :ignore
      # - assert error_filter.for_status('500') == nil

      # compatibility for deprecated config setting; split classes by ',' and store as ignore_classes
      def test_ignore_errors
        with_config :'error_collector.ignore_errors' => 'TestExceptionA,TestExceptionC' do
          @error_filter.reload
          assert_equal :ignored, @error_filter.type_for_exception(TestExceptionA.new)
          assert_nil @error_filter.type_for_exception(TestExceptionB.new)
        end
      end

      def test_expected_classes
        with_config :'error_collector.expected_classes' => ['TestExceptionA', 'TestExceptionC'] do
          @error_filter.reload
          assert_equal :expected, @error_filter.type_for_exception(TestExceptionA.new)
          assert_nil @error_filter.type_for_exception(TestExceptionB.new)
        end
      end

      def test_expected_messages
        with_config :'error_collector.expected_messages' => {'TestExceptionA' => ['message one', 'message two']} do
          @error_filter.reload
          assert_equal :expected, @error_filter.type_for_exception(TestExceptionA.new('message one'))
          assert_equal :expected, @error_filter.type_for_exception(TestExceptionA.new('message two'))
          assert_nil @error_filter.type_for_exception(TestExceptionA.new('message three'))
          assert_nil @error_filter.type_for_exception(TestExceptionB.new('message one'))
        end
      end

      # TODO: test - parses error_collector.expected_status_codes as String
    end
  end
end