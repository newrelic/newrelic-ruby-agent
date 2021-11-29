# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

class LoggerInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @written = StringIO.new
    @logger = ::Logger.new(@written)

    # Set formatter to avoid different defaults across versions/environments
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{severity} - #{progname} - #{msg}\n"
    end

    NewRelic::Agent.instance.stats_engine.reset!
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.reset!
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

    define_method("test_records_multiple_calls_#{name}") do
      @logger.send(name, "A message")
      @logger.send(name, "Another")

      assert_equal(2, @written.string.lines.count)
      assert_match(/#{name.upcase}.*A message/, @written.string)
      assert_match(/#{name.upcase}.*Another/, @written.string)
      assert_logging_metrics(name.upcase, 2)
    end

    # logger#debug(Object.new)
    define_method("test_records_not_a_string_#{name}") do
      @logger.send(name, Object.new)
      assert_equal(1, @written.string.lines.count)
      assert_match(/#{name.upcase}.*<Object.*>/, @written.string)
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

  def test_still_skips_levels
    @logger.level = ::Logger::INFO
    @logger.debug("Won't see this")
    assert_equal(0, @written.string.lines.count)
    refute_any_logging_metrics()
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

  def test_nil_severity
    @logger.log(nil, "A message", "progname")
    assert_equal(1, @written.string.lines.count)
    assert_match(/ANY.*progname.*A message/, @written.string)
    assert_logging_metrics("ANY")
  end

  def test_skips_when_set
    @logger.mark_skip_instrumenting
    @logger.log(1_000_000, "A message", "progname")

    assert_equal(1, @written.string.lines.count)
    assert_match(/ANY.*progname.*A message/, @written.string)
    refute_any_logging_metrics()
  end

  def refute_any_logging_metrics
    assert_metrics_recorded_exclusive([])
  end

  def assert_logging_metrics(label, count = 1)
    assert_metrics_recorded_exclusive({
      "Logging/lines"          => { :call_count => count },
      "Logging/lines/#{label}" => { :call_count => count },
      "Logging/size" => {},
      "Logging/size/#{label}" => {},
      "Supportability/API/increment_metric" => {},
      "Supportability/API/record_metric" => {}
    })
  end
end
