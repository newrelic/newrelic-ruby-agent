# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# disabling for anything that might run Minitest 4.x
if RUBY_VERSION >= '2.7.0'
  require 'fileutils'
  require 'minitest/autorun'
  require 'minitest/stub_const'
  require_relative '../multiverse/lib/multiverse'
  require_relative '../minitest/test_time_reporter'

  class TimeReporterTest < Minitest::Test
    PARSED_RESULT = ['Minitest::Test#woot', 0.12346]

    def result
      test = Minitest::Test.new(:woot)
      test.instance_variable_set(:@time, 0.123456)
      test
    end

    def setup
      @reporter = TestTimeReporter.new
      @reporter.start_time = Time.now # needed to avoid NilClass errors
      @reporter.record(result)
    end

    def test_record_adds_result_to_test_times
      setup
      reporter = TestTimeReporter.new
      reporter.record(result)

      assert_equal([PARSED_RESULT], reporter.instance_variable_get(:@test_times))
    end

    def test_report_prints_outside_multiverse
      setup
      ::Multiverse.send(:remove_const, :ROOT)

      refute(defined?(::Multiverse::ROOT), 'Multiverse::ROOT is defined.')
      @reporter.instance_variable_set(:@test_times, [PARSED_RESULT])
      assert_output(/Ten slowest tests/) { @reporter.report } if ENV["VERBOSE_TEST_OUPUT"]
    end

    def test_report_does_not_print_inside_multiverse
      setup
      ::Multiverse.stub_const(:ROOT, true) do
        @reporter.instance_variable_set(:@test_times, [result])
        assert_silent { @reporter.report }
      end
    end

    def test_report_adds_data_to_file
      time_report = File.join(File.expand_path(File.dirname(__FILE__)), 'tmp')
      setup
      TestTimeReporter.stub_const(:TEST_TIME_REPORT, time_report) do
        @reporter.report

        assert_match(/#{result.instance_variable_get(:@NAME)}/, File.read(time_report))
      end
      File.delete(time_report)
    end
  end
end
