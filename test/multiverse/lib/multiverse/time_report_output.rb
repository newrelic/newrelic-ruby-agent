# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module TimeReportOutput
  def sort_and_print_test_times
    if File.exist?(Multiverse::TEST_TIME_REPORT_PATH)
      test_times = time_report_to_hash(File.readlines(Multiverse::TEST_TIME_REPORT_PATH))
      test_times = hash_values_to_float(test_times)
      print_top_ten(sort_ten_slowest_tests(test_times))
    else
      puts yellow('Test timing data not found.') if ENV["VERBOSE_TEST_OUTPUT"]
    end
  end

  private

  def time_report_to_hash(time_report_lines)
    time_report_lines.map { |line| line.delete("\n", '') }.each_slice(2).to_h
  end

  # TODO: OLD RUBIES - When we support only Ruby 2.4+, refactor to use #transform_values instead
  def hash_values_to_float(original_hash)
    float_values = {}
    original_hash.each { |k, v| float_values[k] = v.to_f }
    float_values
  end

  def print_top_ten(top_ten)
    return unless ENV["VERBOSE_TEST_OUTPUT"]

    puts "\n====== Ten slowest tests ======\n"
    top_ten.each_with_index do |element, index|
      puts "#{index + 1}. #{element.join(': ')}"
    end
  end

  def sort_ten_slowest_tests(test_times)
    test_times.sort_by { |_k, v| v }.reverse!.slice(0, 10)
  end
end
