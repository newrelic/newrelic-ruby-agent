# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class MarshalConfigTest < Minitest::Test
  include MultiverseHelpers

  JSON_MISSING_MESSAGE = "JSON marshaller requested, but the 'json' gem was not available."

  def setup
    NewRelic::Agent.stubs(:logger).returns(NewRelic::Agent::MemoryLogger.new)
  end

  def test_agent_does_not_start_with_no_json_marshaller
    assert_equal false, NewRelic::Agent.instance.agent_should_start?
    assert logger_whined_about_json?, "Log should've contained: #{JSON_MISSING_MESSAGE}"
  end

  def logger_whined_about_json?
    NewRelic::Agent.logger.messages.flatten.any? { |msg| msg.to_s.include? JSON_MISSING_MESSAGE }
  end
end
