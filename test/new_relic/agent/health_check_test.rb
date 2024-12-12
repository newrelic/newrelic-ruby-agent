# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'fileutils'
require_relative '../../test_helper'

class NewRelicHealthCheckTest < Minitest::Test
  # example:
  # health-bc21b5891f5e44fc9272caef924611a8.yml
  # healthy: false
  # status: Agent has shutdown
  # last_error: NR-APM-1000
  # status_time_unix_nano: 1724953624761000000
  # start_time_unix_nano: 1724953587605000000

  # maybe delete the file every time?
  # def teardown
  #   FileUtils.rm_rf('health')
  # end

  def test_yaml_health_file_written_to_delivery_location
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.directory?('health'), 'Directory not found'
        assert File.exist?('health/health-abc123.yml'), 'File not found'
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  # This might be on init...
  def test_yaml_health_file_logs_error_when_delivery_location_invalid
  end

  def test_yaml_file_generated_if_superagent_fleet_id_present
  end

  def test_yaml_file_not_generated_if_superagent_fleet_id_absent
  end

  def test_yaml_file_name_has_health_plus_uuid_without_hyphens
    health_check = NewRelic::Agent::HealthCheck.new
    # ex: health-bc21b5891f5e44fc9272caef924611a8.yml
    assert_match /health-(.*){32}\.ya?ml/, health_check.file_name
  end

  def test_yaml_health_file_written_on_interval
    with_config(:'superagent.health.frequency' => 5) do

    end
  end

  def test_agent_logs_errors_if_yaml_health_file_writing_fails
  end

  def test_yaml_file_has_health_field
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.readlines('health/health-abc123.yml').grep(/health:/).any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_status_field
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.readlines('health/health-abc123.yml').grep(/status:/).any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_last_error_field_when_status_not_healthy
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.readlines('health/health-abc123.yml').grep(/last_error:/).any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_does_not_have_last_error_field_when_status_healthy
  end

  def test_yaml_file_has_start_time_unix_nano
    # TODO - validate timestamp
    # TODO - validate timestamp same for every file created by that instance
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.readlines('health/health-abc123.yml').grep(/start_time_unix_nano:/).any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_has_status_time_unix_nano
    # status_time_unix_nano:
    # timestamp present
    # timestamp in nanoseconds => milliseconds * 1000000
    with_config(:'superagent.health.delivery_location' => 'health/') do
      NewRelic::Agent::GuidGenerator.stub(:generate_guid, 'abc123') do
        health_check = NewRelic::Agent::HealthCheck.new
        health_check.write_file

        assert File.readlines('health/health-abc123.yml').grep(/status_time_unix_nano:/).any?
      end
    end
  ensure
    FileUtils.rm_rf('health')
  end

  def test_yaml_file_fully_regenerated_on_each_interval
  end

  def test_unique_health_file_exists_per_process
    # puma scenario?
  end

  def test_supportability_metric_generated_at_agent_startup
    # Supportability/SuperAgent/Health/enabled
  end

  ## ADD MORE TESTS FOR ERROR CODE BEHAVIOR
end
