# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../.github/workflows/scripts/slack_notifications/gem_notifier'

class GemNotifications < Minitest::Test
  def successful_http_response
    response = MiniTest::Mock.new
    response.expect(:success?, true)
  end

  def unsuccessful_http_response
    response = MiniTest::Mock.new
    response.expect(:success?, false)
  end

  def http_get_response
    [{"created_at" => "2001-07-18T16:15:29.083Z", "platform" => "ruby", "number" => "4.0.0.preview"},
      {"created_at" => "2001-07-18T16:15:29.083Z", "platform" => "ruby", "number" => "3.0.0.rc1"},
      {"created_at" => "2001-07-18T16:15:29.083Z", "platform" => "ruby", "number" => "3.0.0"},
      {"created_at" => "1997-05-23T16:15:29.083Z", "platform" => "java", "number" => "2.0.0"},
      {"created_at" => "1993-06-11T16:15:29.083Z", "platform" => "ruby", "number" => "1.0.0"}]
  end

  def test_valid_gem_name
    response = successful_http_response()
    HTTParty.stub(:get, response) do
      assert GemNotifier.verify_gem("puma!")
    end
  end

  def test_invalid_gem_name
    response = unsuccessful_http_response()
    HTTParty.stub(:get, response) do
      assert_nil GemNotifier.verify_gem("TrexRawr!")
    end
  end

  def test_valid_github_diff
    response = successful_http_response()
    HTTParty.stub(:get, response) do
      assert_equal true, GemNotifier.github_diff('valid_git_diff', '1.2', '1.1')
    end
  end

  def test_invalid_github_diff
    response = unsuccessful_http_response()
    HTTParty.stub(:get, response) do
      assert_equal false, GemNotifier.github_diff('invalid_git_diff', '1.2', '1.1')
    end
  end

  def test_get_gem_info_returns_array
    versions = GemNotifier.gem_versions(http_get_response())
    assert_instance_of Array, versions
  end

  def test_get_gem_info_max_size
    versions = GemNotifier.gem_versions(http_get_response())
    assert_equal true, versions.size == 2
  end

  def test_newest_version_can_be_a_preview_or_rc_or_beta_release
    versions = GemNotifier.gem_versions(http_get_response())
    assert_equal '4.0.0.preview', versions.first['number']
  end

  def test_previous_version_must_be_a_stable_release
    versions = GemNotifier.gem_versions(http_get_response())
    assert_equal '3.0.0', versions.last['number']
  end

  def test_gem_updated_true
    assert_equal true, GemNotifier.gem_updated?([{"created_at" => "#{Time.now}"}])
  end

  def test_gem_updated_false
    assert_equal false, GemNotifier.gem_updated?([{"created_at" => "1993-06-11T17:31:14.298Z"}])
  end

  def test_interpolate_github_url_one_arg
    gem_name = "stegosaurus"
    assert_raises(ArgumentError) { GemNotifier.interpolate_github_url(gem_name) }
  end

  def test_interpolate_github_url
    gem_name, newest, previous = "stegosaurus", "2.0", "1.0"
    assert_kind_of String, GemNotifier.interpolate_github_url(gem_name, newest, previous)
  end

  def test_interpolate_rubygems_url_one_arg
    assert_raises(ArgumentError) { GemNotifier.interpolate_rubygems_url() }
  end

  def test_interpolate_rubygems_url
    gem_name = "velociraptor"
    assert_kind_of String, GemNotifier.interpolate_rubygems_url(gem_name)
  end
end
