# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'fileutils'
require_relative '../../test_helper'

class NewRelicHealthCheckTest < Minitest::Test
  # example
  # file name: health-bc21b5891f5e44fc9272caef924611a8.yml
  # healthy: true
  # status: Agent has shutdown
  # last_error: NR-APM-099
  # status_time_unix_nano: 1724953624761000000
  # start_time_unix_nano: 1724953587605000000

  def teardown
    mocha_teardown
  end

  def test_yaml_health_file_written_to_delivery_location
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)

        assert File.directory?('health'), 'Directory not found'
        assert File.exist?('health/health-abc123.yml'), 'File not found' # rubocop:disable Minitest/AssertPathExists
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_health_file_written_to_delivery_location_with_file_path_prefix
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'file://health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)

        assert File.directory?('./health'), 'Directory not found'
        assert File.exist?('./health/health-abc123.yml'), 'File not found' # rubocop:disable Minitest/AssertPathExists
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_name_has_health_plus_uuid_without_hyphens
    health_check = NewRelic::Agent::HealthCheck.new

    # ex: health-bc21b5891f5e44fc9272caef924611a8.yml
    assert_match(/^health-[0-9a-f]{32}\.ya?ml$/, health_check.send(:file_name))
  end

  def test_write_file_called_on_interval
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '3',
      'NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'abc',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      health_check = NewRelic::Agent::HealthCheck.new
      health_check.stub(:write_file, nil) do
        health_check.expects(:sleep).with(3).times(3)
        health_check.expects(:write_file).times(3).then.returns(nil).then.returns(nil).then.raises('whoa!')
        health_check.create_and_run_health_check_loop.join
      end
    end
  end

  def test_create_and_run_health_check_loop_exits_after_shutdown
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '3',
      'NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'abc',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      health_check = NewRelic::Agent::HealthCheck.new
      health_check.stub(:write_file, nil) do
        health_check.expects(:sleep).with(3).times(1)
        health_check.expects(:write_file).times(1).then.returns(nil)
        health_check.update_status(NewRelic::Agent::HealthCheck::SHUTDOWN)
        health_check.create_and_run_health_check_loop.join
      end
    end
  end

  def test_write_file_sets_continue_false_when_error
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        File.stub(:write, ->(arg1, arg2) { raise 'boom!' }) do
          health_check = NewRelic::Agent::HealthCheck.new

          assert(health_check.instance_variable_get(:@continue))
          health_check.send(:write_file)

          refute(health_check.instance_variable_get(:@continue))
        end
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_frequency_defaults_to_five
    # deliberately not setting the `NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY` env var
    health_check = NewRelic::Agent::HealthCheck.new

    assert_equal 5, health_check.instance_variable_get(:@frequency)
  end

  def test_create_file_path_sets_continue_false_when_error_raised
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        File.stub(:directory?, ->(arg1) { raise 'boom!' }) do
          health_check = NewRelic::Agent::HealthCheck.new

          assert(health_check.instance_variable_get(:@continue))
          health_check.send(:create_file_path)

          refute(health_check.instance_variable_get(:@continue))
        end
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_healthy_field
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-abc123.yml').grep(/healthy:/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_status_field
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-abc123.yml').grep(/status:/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_last_error_field_when_status_not_healthy
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.update_status(NewRelic::Agent::HealthCheck::INVALID_LICENSE_KEY)
        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-abc123.yml').grep(/last_error:/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_does_not_have_last_error_field_when_status_healthy
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.update_status(NewRelic::Agent::HealthCheck::HEALTHY)
        health_check.send(:write_file)

        refute_predicate File.readlines('health/health-abc123.yml').grep(/last_error:/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_nano_time_in_correct_format
    health_check = NewRelic::Agent::HealthCheck.new
    time = health_check.send(:nano_time)

    assert_instance_of(Integer, time)
    assert(time.to_s.length >= 19)
  end

  def test_yaml_file_has_same_start_time_unix_every_write
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, '1') do
        health_check = NewRelic::Agent::HealthCheck.new
        start_time = health_check.instance_variable_get(:@start_time_unix_nano)
        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-1.yml').grep(/start_time_unix_nano: #{start_time}/), :any?

        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-1.yml').grep(/start_time_unix_nano: #{start_time}/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_status_time_unix_nano
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)

        assert_predicate File.readlines('health/health-abc123.yml').grep(/status_time_unix_nano:/), :any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_new_status_time_each_write
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, '1') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.send(:write_file)
        # on a healthy file, the third index/fourth line should hold the status_time_unix_nano data
        first_status_time = File.readlines('health/health-1.yml')[3]
        health_check.send(:write_file)
        second_status_time = File.readlines('health/health-1.yml')[3]

        refute_equal(first_status_time, second_status_time)
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_agent_health_started_if_required_info_present
    with_environment('NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'landslide',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => '/health',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '5') do
      log = with_array_logger(:debug) do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.create_and_run_health_check_loop
      end

      assert_log_contains(log, 'Agent control health check conditions met. Starting health checks.')
      refute_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_FLEET_ID not found')
      refute_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION not found')
      refute_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY zero or less')
    end
  end

  def test_agent_health_not_generated_if_agent_control_fleet_id_absent
    with_environment('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => '/health',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '5') do
      log = with_array_logger(:debug) do
        health_check = NewRelic::Agent::HealthCheck.new
        # loop should exit before write_file is called
        # raise an error if it's invoked
        health_check.stub(:write_file, -> { raise 'kaboom!' }) do
          health_check.create_and_run_health_check_loop
        end
      end

      assert_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_FLEET_ID not found')
      refute_log_contains(log, 'Agent control health check conditions met. Starting health checks.')
    end
  end

  def test_agent_health_not_generated_if_delivery_location_absent
    with_environment('NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'mykonos',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '5') do
      log = with_array_logger(:debug) do
        health_check = NewRelic::Agent::HealthCheck.new
        # loop should exit before write_file is called
        # raise an error if it's invoked
        health_check.stub(:write_file, -> { raise 'kaboom!' }) do
          health_check.create_and_run_health_check_loop
        end
      end

      assert_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION not found')
      refute_log_contains(log, 'Agent control health check conditions met. Starting health checks.')
    end
  end

  def test_agent_health_not_generated_if_frequency_is_zero
    with_environment('NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'anchors-away',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => '/health',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '0') do
      log = with_array_logger(:debug) do
        health_check = NewRelic::Agent::HealthCheck.new
        # loop should exit before write_file is called
        # raise an error if it's invoked
        health_check.stub(:write_file, -> { raise 'kaboom!' }) do
          health_check.create_and_run_health_check_loop
        end
      end

      assert_log_contains(log, 'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY zero or less')
      refute_log_contains(log, 'Agent control health check conditions met. Starting health checks.')
    end
  end

  def test_agent_health_supportability_metric_generated_recorded_when_health_check_loop_starts
    NewRelic::Agent.instance.stats_engine.clear_stats

    with_environment('NEW_RELIC_AGENT_CONTROL_FLEET_ID' => 'landslide',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => '/health',
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '5') do
      health_check = NewRelic::Agent::HealthCheck.new
      health_check.create_and_run_health_check_loop

      assert_metrics_recorded({'Supportability/AgentControl/Health/enabled' => {call_count: 1}})
    end
  end

  def test_update_status_is_a_no_op_when_health_checks_disabled
    with_environment('NEW_RELIC_AGENT_CONTROL_FLEET_ID' => nil,
      'NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION' => nil,
      'NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY' => '0') do
      health_check = NewRelic::Agent::HealthCheck.new

      assert_equal NewRelic::Agent::HealthCheck::HEALTHY, health_check.instance_variable_get(:@status)

      health_check.create_and_run_health_check_loop
      health_check.update_status(NewRelic::Agent::HealthCheck::SHUTDOWN)

      assert_equal NewRelic::Agent::HealthCheck::HEALTHY, health_check.instance_variable_get(:@status)
    end
  end

  def test_update_message_works_with_http_arrays
    health_check = NewRelic::Agent::HealthCheck.new
    result = health_check.update_status(NewRelic::Agent::HealthCheck::HTTP_ERROR, ['401', :preconnect])

    assert_equal 'HTTP error response code [401] recevied from New Relic while sending data type [preconnect]', result
  end
end
