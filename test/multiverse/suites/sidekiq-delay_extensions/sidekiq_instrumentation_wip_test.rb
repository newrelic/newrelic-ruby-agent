# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers_wip'

class SidekiqInstrumentationTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent

  def after_setup
    super
    NewRelic::Agent.drop_buffered_data
  end

  include SidekiqTestHelpers

  def test_running_a_job_produces_a_healthy_segment
    segment = run_job

    assert_equal 'Nested/OtherTransaction/SidekiqJob/Dolce/long_running_task', segment.name
  end
end
