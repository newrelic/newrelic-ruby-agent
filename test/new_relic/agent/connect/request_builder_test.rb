# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', '..','test_helper'))
require 'new_relic/agent/agent'

class NewRelic::Agent::Agent::RequestBuilderTest < Minitest::Test

  def setup
    @service = default_service
    NewRelic::Agent.reset_config
    @request_builder = NewRelic::Agent::Connect::RequestBuilder.new(
        @service, NewRelic::Agent.config)
  end

  def test_connect_settings_have_environment_report
    assert @request_builder.environment_report.detect{ |(k, _)|
      k == 'Gems'
    }, "expected connect_settings to include gems from environment"
  end

  def test_environment_for_connect_negative
    with_config(:send_environment_info => false) do
      assert_equal [], @request_builder.environment_report
    end
  end

  def test_sanitize_environment_report
    environment_report = ['not empty']
    @service.stubs(:valid_to_marshal?).returns(true)
    assert_equal environment_report, @request_builder.sanitize_environment_report(environment_report)
  end

  def test_sanitize_environment_report_cannot_be_serialized
    @service.stubs(:valid_to_marshal?).returns(false)
    assert_equal [], @request_builder.sanitize_environment_report(['not empty'])
  end

  def test_connect_settings
    NewRelic::Agent.config.expects(:app_names).twice.returns(["apps"])

    keys = %w(pid host identifier display_host app_name language agent_version environment settings).map(&:to_sym)

    settings = @request_builder.connect_payload
    keys.each do |k|
      assert_includes(settings.keys, k)
      refute_nil(settings[k], "expected a value for #{k}")
    end
  end

  def test_connect_settings_includes_correct_identifier
    NewRelic::Agent.config.expects(:app_names).twice.returns(["b", "a", "c"])
    NewRelic::Agent::Connect::RequestBuilder.any_instance.stubs(:local_host).returns('lo-calhost')
    @environment_report = {}

    settings = @request_builder.connect_payload

    assert_equal settings[:identifier], "ruby:lo-calhost:a,b,c"
  end

  def test_connect_settings_includes_labels_from_config
    with_config({:labels => {'Server' => 'East'}}) do
      expected = [ {"label_type"=>"Server", "label_value"=>"East"} ]
      assert_equal expected, @request_builder.connect_payload[:labels]
    end
  end

  def test_connect_settings_includes_labels_from_semicolon_separated_config
    with_config(:labels => "Server:East;Server:West;") do
      expected = [
        {"label_type"=>"Server", "label_value"=>"West"}
      ]
      assert_equal expected, @request_builder.connect_payload[:labels]
    end
  end

  def test_event_data_hash_returns_default_values
    NewRelic::Agent.config.add_config_for_testing(:'analytics_events.max_samples_stored' => 1000)
    NewRelic::Agent.config.add_config_for_testing(:'custom_insights_events.max_samples_stored' => 1000)
    NewRelic::Agent.config.add_config_for_testing(:'error_collector.max_event_samples_stored' => 1000)

    expected = {
      :harvest_limits => {
        :analytic_event_data => 1000,
        :custom_event_data => 1000,
        :error_event_data => 1000
      }
    }

    assert_equal(expected, @request_builder.event_data_hash)
  end

end