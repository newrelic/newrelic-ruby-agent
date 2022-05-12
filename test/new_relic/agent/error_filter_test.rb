# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'

class TestExceptionA < StandardError; end

class TestExceptionB < StandardError; end

class TestExceptionC < StandardError; end

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

      def test_ignore_status_codes
        with_config :'error_collector.ignore_status_codes' => '401,405-409,501' do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new, 401)
          assert @error_filter.ignore?(TestExceptionA.new, 501)
          (405..409).each do |c|
            assert @error_filter.ignore?(TestExceptionA.new, c)
          end
          refute @error_filter.ignore?(TestExceptionA.new, 404)
        end
      end

      def test_ignore_status_codes_by_array
        with_config :'error_collector.ignore_status_codes' => ['401', '405-409', 501] do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new, 401)
          assert @error_filter.ignore?(TestExceptionA.new, 501)
          (405..409).each do |c|
            assert @error_filter.ignore?(TestExceptionA.new, c)
          end
          refute @error_filter.ignore?(TestExceptionA.new, 404)
        end
      end

      def test_ignore_method
        @error_filter.ignore('TestExceptionA', ['ArgumentError'])
        assert @error_filter.ignore?(TestExceptionA.new)
        assert @error_filter.ignore?(ArgumentError.new)
        refute @error_filter.ignore?(TestExceptionB.new)

        @error_filter.ignore('TestExceptionB', {'TestExceptionC' => ['message one', 'message two']})
        assert @error_filter.ignore?(TestExceptionB.new)
        assert @error_filter.ignore?(TestExceptionC.new('message one'))
        assert @error_filter.ignore?(TestExceptionC.new('message two'))
        refute @error_filter.ignore?(TestExceptionC.new('message three'))

        @error_filter.reset
        refute @error_filter.ignore?(TestExceptionA.new)

        @error_filter.ignore('401,405-409', [500, '505-509'])
        assert @error_filter.ignore?(TestExceptionA.new, 401)
        assert @error_filter.ignore?(TestExceptionA.new, 407)
        assert @error_filter.ignore?(TestExceptionA.new, 500)
        assert @error_filter.ignore?(TestExceptionA.new, 507)
        refute @error_filter.ignore?(TestExceptionA.new, 404)
      end

      def test_skip_invalid_status_codes
        with_config :'error_collector.ignore_status_codes' => '401,sausage,foo-bar,500' do
          @error_filter.load_all
          refute @error_filter.ignore?(TestExceptionA.new, 400)
          assert @error_filter.ignore?(TestExceptionA.new, 401)
          assert @error_filter.ignore?(TestExceptionA.new, 500)
        end
      end

      def test_ignore_integer_status_codes
        with_config :'error_collector.ignore_status_codes' => 418 do
          @error_filter.load_all
          assert @error_filter.ignore?(TestExceptionA.new, 418)
        end
      end

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

      def test_expected_status_codes
        with_config :'error_collector.expected_status_codes' => '401,405-409,501' do
          @error_filter.load_all
          assert @error_filter.expected?(TestExceptionA.new, 401)
          assert @error_filter.expected?(TestExceptionA.new, 501)
          (405..409).each do |c|
            assert @error_filter.expected?(TestExceptionA.new, c)
          end
          refute @error_filter.expected?(TestExceptionA.new, 404)
        end
      end

      def test_expect_method
        @error_filter.expect('TestExceptionA', ['ArgumentError'])
        assert @error_filter.expected?(TestExceptionA.new)
        assert @error_filter.expected?(ArgumentError.new)
        refute @error_filter.expected?(TestExceptionB.new)

        @error_filter.expect('TestExceptionB', {'TestExceptionC' => ['message one', 'message two']})
        assert @error_filter.expected?(TestExceptionB.new)
        assert @error_filter.expected?(TestExceptionC.new('message one'))
        assert @error_filter.expected?(TestExceptionC.new('message two'))
        refute @error_filter.expected?(TestExceptionC.new('message three'))

        @error_filter.reset
        refute @error_filter.expected?(TestExceptionA.new)

        @error_filter.expect('401,405-409', ['500', '505-509'])
        assert @error_filter.expected?(TestExceptionA.new, 401)
        assert @error_filter.expected?(TestExceptionA.new, 407)
        assert @error_filter.expected?(TestExceptionA.new, 500)
        assert @error_filter.expected?(TestExceptionA.new, 507)
        refute @error_filter.expected?(TestExceptionA.new, 404)
      end

      def test_empty_settings_do_not_overwrite_existing_settings
        @error_filter.expect(['TestExceptionA'])

        with_config 'error_collector.expected_classes' => [] do
          @error_filter.load_all
          assert @error_filter.expected?(TestExceptionA.new)
        end
      end
    end
  end
end
