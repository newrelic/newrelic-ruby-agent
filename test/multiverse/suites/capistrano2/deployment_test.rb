# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fake_rpm_site'

class DeploymentTest < Minitest::Test
  def setup
    $rpm_site ||= NewRelic::FakeRpmSite.new
    $rpm_site.reset
    $rpm_site.run
  end

  def test_deploys_to_configured_application
    cap_it
    assert_deployment_value("application_id", "test")
  end

  def test_deploys_with_commandline_parameter
    cap_it("-s newrelic_user=someone -s newrelic_appname=somewhere")
    assert_deployment_value("user",           "someone")
    assert_deployment_value("application_id", "somewhere")
  end

  def assert_deployment_value(key, value)
    assert_equal(1, $rpm_site.requests.count)
    assert_equal(value, $rpm_site.requests.first["deployment"][key])
  end

  def cap_it(options="")
    cmd = "cap newrelic:notice_deployment #{options}"
    output = with_environment('FAKE_RPM_SITE_PORT' => $rpm_site.port.to_s) do
      `#{cmd}`
    end
    assert $?.success?, "cap command '#{cmd}' failed with output: #{output}"
  end
end
