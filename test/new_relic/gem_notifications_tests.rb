# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../.github/workflows/scripts/slack_gem_notifications/notifications_methods'

class GemNotifications < Minitest::Test
  def invalid_gem_response
    response = MiniTest::Mock.new
    response.expect :success?, false
  end

  def valid_gem_response
    response = MiniTest::Mock.new
    response.expect :success?, true
  end

  def http_get_response
    [{"created_at" => "2001-07-18T16:15:29.083Z", "platform" => "ruby", "number" => "3.0.0"},
      {"created_at" => "1997-05-23T16:15:29.083Z", "platform" => "java", "number" => "2.0.0"},
      {"created_at" => "1993-06-11T16:15:29.083Z", "platform" => "ruby", "number" => "1.0.0"}]
  end

  def test_valid_gem_name
    response = valid_gem_response()
    HTTParty.stub :get, response do
      assert verify_gem("puma!")
    end
  end

  def test_invalid_gem_name
    response = invalid_gem_response()
    HTTParty.stub :get, response do
      assert_nil verify_gem("TrexRawr!")
    end
  end

  def test_get_gem_info_returns_array
    versions = gem_versions(http_get_response())
    assert_instance_of Array, versions
  end

  def test_get_gem_info_max_size
    versions = gem_versions(http_get_response())
    assert_equal true, versions.size == 2
  end

  def test_gem_updated
    assert_equal true, gem_updated?([{"created_at" => "#{Time.now}"}])
    assert_equal false, gem_updated?([{"created_at" => "1993-06-11T17:31:14.298Z"}])
  end

  def test_send_bot_input_size
    assert_raises(ArgumentError) { send_bot() }
    assert_raises(ArgumentError) { send_bot("tyrannosaurus") }
    HTTParty.stub :post, nil do
      assert_nil send_bot("tyrannosaurus", [{"number" => "83.6"}, {"number" => "66.0"}])
    end
  end
end
