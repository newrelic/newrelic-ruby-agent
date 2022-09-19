# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'suite'
require_relative 'new_relic_runnable'

MINITEST_REPORTER_CLASS_NAME = if defined?(Minitest::VERSION)
  Minitest::StatisticsReporter
elsif defined?(MiniTest::VERSION)
  MiniTest::StatisticsReporter
else
  raise 'Minitest not loaded'
end

class SuiteTimeReporter < MINITEST_REPORTER_CLASS_NAME
  attr_accessor :suite_times, :suite_start_times, :tests
  SUITE_TIME_REPORT = File.join(File.expand_path(File.dirname(__FILE__)), 'minitest_suite_time_report')

  def initialize(options = {})
    super
    @suite_start_times = {}
    @suite_times = []
    @tests = []
  end

  def before_test(test)
    last_test = test_class(tests.last)
    suite_changed = last_test.nil? || last_test.name != test.class.name

    return unless suite_changed

    after_suite(last_test) if last_test
    before_suite(test_class(test))
  end

  def record(result)
    super
    tests << result
  end

  def report
    super
    if last_suite = test_class(tests.last)
      after_suite(last_suite)
    end
    output_report unless defined?(Multiverse::ROOT)
    write_results(@suite_times)
  end

  private

  def before_suite(suite)
    @suite_start_times[suite] = Time.now
  end

  def test_class(result)
    if result.nil?
      nil
    elsif result.respond_to?(:klass)
      Suite.new(result.klass)
    elsif result.is_a?(Class)
      result.name
    else
      Suite.new(result.class.name)
    end
  end

  def after_suite(suite)
    duration = suite_duration(suite)
    @suite_times << [suite.name, duration]
  end

  def suite_duration(suite)
    start_time = @suite_start_times.delete(suite.name)
    if start_time.nil?
      0
    else
      Time.now - start_time
    end
  end

  def sorted_suite_times
    @suite_times.to_h.sort_by { |k, v| v }.reverse!
  end

  def output_report
    puts "\n====== Suite Timing Report ======\n"
    sorted_suite_times.each_with_index do |element, index|
      puts "#{index + 1}. #{element.join(': ')}"
    end
  end

  def write_results(results)
    File.open(SUITE_TIME_REPORT, "a") do |f|
      f.puts(@suite_times)
    end
  end
end
