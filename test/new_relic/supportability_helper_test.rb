# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class NewRelic::SupportabilityHelperTest < Minitest::Test
  def teardown
    NewRelic::Agent.shutdown
    super
  end

  include NewRelic::SupportabilityHelper

  def test_valid_api_argument_class_truthy
    assert valid_api_argument_class?({foo: :bar}, 'headers', Hash)
  end

  def test_valid_api_argument_class_falsey
    log = with_array_logger do
      NewRelic::Agent.manual_start

      refute valid_api_argument_class?('bogus', 'headers', Hash)
    end

    assert_log_contains(log, /Bad argument passed to #block/)
    assert_log_contains(log, /Expected Hash for `headers` but got String/)
  end

  def test_record_api_supportability_metric_not_found
    logger = MiniTest::Mock.new
    logger.expect :debug, [], [/not found/]

    NewRelic::Agent.stub :logger, logger do
      record_api_supportability_metric(:start_over_rover)
      logger.verify
    end
  end
end
