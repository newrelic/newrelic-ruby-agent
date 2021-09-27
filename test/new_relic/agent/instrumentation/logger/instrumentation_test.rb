# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path '../../../../../test_helper', __FILE__
require 'new_relic/agent/instrumentation/logger'

class NewRelic::Agent::Instrumentation::LoggerTest < Minitest::Test
  def setup
    @written = StringIO.new
    @logger = ::Logger.new(@written)
    NewRelic::Agent.instance.stats_engine.reset!
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.reset!
  end

  def test_doesnt_touch_construction
    assert_metrics_recorded_exclusive []
  end

  LEVELS = [
    ['debug', Logger::DEBUG],
    ['error', Logger::ERROR],
    ['fatal', Logger::FATAL],
    ['info',  Logger::INFO],
    ['warn',  Logger::WARN],
  ]

  LEVELS.each do |(name, level)|
    # logger#debug("message")
    define_method("test_records_#{name}") do
      @logger.send(name, "A message")
      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*A message/, @written.string)
      assert_logging_metrics(name.upcase)
    end

    # logger#debug { "message" }
    define_method("test_records_with_block#{name}") do
      @logger.send(name) do
        "A message"
      end

      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*A message/, @written.string)
      assert_logging_metrics(name.upcase)
    end

    # logger#log(Logger::DEBUG, "message")
    define_method("test_records_by_log_method_#{name}") do
      @logger.log(level, "A message")
      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*A message/, @written.string)
      assert_logging_metrics(name.upcase)
    end

    # logger#log(Logger::DEBUG} { "message" }
    define_method("test_records_by_log_method_with_block_#{name}") do
      @logger.log(level) { "A message" }
      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*A message/, @written.string)
      assert_logging_metrics(name.upcase)
    end

    # logger#log(Logger::DEBUG, "message", "progname")
    define_method("test_records_by_log_method_plus_progname_#{name}") do
      @logger.log(level, "A message", "progname")
      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*progname.*A message/, @written.string)
      assert_logging_metrics(name.upcase)
    end
  end

  def test_unknown
    @logger.unknown("A message")
    assert_equal(1, @written.string.lines.count)
    assert_match(/ANY.*A message/, @written.string)
    assert_logging_metrics("ANY")
  end

  def test_really_high_level
    @logger.log(1_000_000, "A message")
    assert_equal(1, @written.string.lines.count)
    assert_match(/ANY.*A message/, @written.string)
    assert_logging_metrics("ANY")
  end

  def test_really_high_level_with_progname
    @logger.log(1_000_000, "A message", "progname")
    assert_equal(1, @written.string.lines.count)
    assert_match(/ANY.*progname.*A message/, @written.string)
    assert_logging_metrics("ANY")
  end

  def assert_logging_metrics(label)
    assert_metrics_recorded_exclusive [
      "Logging/lines",
      "Logging/lines/#{label}",
      "Logging/size",
      "Logging/size/#{label}",
      "Supportability/API/increment_metric",
      "Supportability/API/record_metric",
    ]
  end
end
