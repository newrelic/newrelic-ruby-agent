# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fake_rpm_site'

class DeploymentTest < Minitest::Test
  def setup
    @rpm_site ||= NewRelic::FakeRpmSite.new
    @rpm_site.reset
    @rpm_site.run
  end

  def test_deploys_to_configured_application
    cap_it
    assert_deployment_value("application_id", "test")
  end

  def test_deploys_with_commandline_parameter
    # Capistrano 3 doesn't provide built-in commandline params -> settings
    # We wire our own up via ENV to test setting out setting custom values
    ENV["NEWRELIC_USER"] = "someone"
    ENV["NEWRELIC_APPNAME"] = "somewhere"

    cap_it
    assert_deployment_value("user",           "someone")
    assert_deployment_value("application_id", "somewhere")
  ensure
    ENV["NEWRELIC_USER"] = nil
    ENV["NEWRELIC_APPNAME"] = nil
  end

  def assert_deployment_value(key, value)
    assert_equal(1, @rpm_site.requests.count)
    assert_equal(value, @rpm_site.requests.first["deployment[#{key}]"])
  end

  def cap_it(options="")
    cmd = "FAKE_RPM_SITE_PORT=#{@rpm_site.port} cap production newrelic:notice_deployment #{options}"
    puts cmd
    output = `#{cmd}`
    puts output unless $?.success?
  end
end
