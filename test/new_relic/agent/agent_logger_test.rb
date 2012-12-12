require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/agent_logger'

class AgentLoggerTest < Test::Unit::TestCase
  def setup
    @config = {}
  end

  def test_initalizes_from_config
    @config[:log_file_path] = "log"
    @config[:log_file_name] = "testlog.log"
    logger = NewRelic::Agent::AgentLogger.new(@config)
    assert_match(/log\/testlog.log/, logger.log_file)
  end

  def test_initalizes_from_override
    inner_log = mock()
    logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})
    assert_equal inner_log, logger.instance_variable_get(:@log)
  end

  def test_forwards_debug_to_logger
    [:fatal, :error, :warn, :info, :debug].each do |level|
      inner_log = mock()
      inner_log.expects(level).with(any_parameters)

      logger = NewRelic::Agent::AgentLogger.new(@config, "", {:log => inner_log})

      logger.send(level, "Boo!")
    end
  end
end
