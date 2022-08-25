# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require 'minitest'

class TestTimeReporter < Minitest::StatisticsReporter
  attr_accessor :test_times

  TEST_TIME_REPORT = File.join(File.expand_path(File.dirname(__FILE__)), 'minitest_time_report')

  def initialize(options = {})
    super
    @test_times = []
  end

  def self.reset_report
    FileUtils.rm_f(TEST_TIME_REPORT)
  end

  def record(result)
    super
    @test_times << ["#{class_name(result)}##{result.name}", (result.time.round(5))]
  end

  def report
    super
    # Multiverse puts out the content at the end of each run, we want to collate
    # and print one report. This is done in the Multiverse::OutputCollector class
    output_report unless defined?(Multiverse::ROOT)
    write_results(@test_times)
  end

  private

  # TODO: allow the # of tests shown and file for output to be custom named
  # def defaults
  #   {
  #     show_count: 15,
  #     test_time_report_filename: File.join(Dir.tmpdir, 'minitest_reporters_report')
  #   }
  # end

  def class_name(result)
    defined?(result.klass) ? result.klass : result.class.name
  end

  def ten_slowest_tests
    @test_times.to_h.sort_by { |k, v| v }.reverse!.slice(0, 10)
  end

  def output_report
    puts "====== Ten slowest tests ======"
    ten_slowest_tests.each_with_index do |element, index|
      puts "#{index + 1}. #{element.join(': ')}"
    end
  end

  # TODO: Find and update the existing test #'s if already present?
  def write_results(results)
    File.open(TEST_TIME_REPORT, "a") do |f|
      f.puts(@test_times)
    end
  end
end
