# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../.github/workflows/scripts/slack_gem_notifications/notifications_methods'
require_relative '../../.github/workflows/scripts/slack_gem_notifications/cve_methods'

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
    [{"created_at" => "2001-07-18T16:15:29.083Z", "platform" => "ruby", "number" => "3.0.0"},
      {"created_at" => "1997-05-23T16:15:29.083Z", "platform" => "java", "number" => "2.0.0"},
      {"created_at" => "1993-06-11T16:15:29.083Z", "platform" => "ruby", "number" => "1.0.0"}]
  end

  def test_valid_gem_name
    response = successful_http_response()
    HTTParty.stub(:get, response) do
      assert verify_gem("puma!")
    end
  end

  def test_invalid_gem_name
    response = unsuccessful_http_response()
    HTTParty.stub(:get, response) do
      assert_nil verify_gem("TrexRawr!")
    end
  end

  def test_valid_github_diff
    response = successful_http_response()
    HTTParty.stub(:get, response) do
      assert_equal true, github_diff('valid_git_diff', '1.2', '1.1')
    end
  end

  def test_invalid_github_diff
    response = unsuccessful_http_response()
    HTTParty.stub(:get, response) do
      assert_equal false, github_diff('invalid_git_diff', '1.2', '1.1')
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

  def test_gem_updated_true
    assert_equal true, gem_updated?([{"created_at" => "#{Time.now}"}])
  end

  def test_gem_updated_false
    assert_equal false, gem_updated?([{"created_at" => "1993-06-11T17:31:14.298Z"}])
  end

  def test_send_bot_zero_args
    assert_raises(ArgumentError) { send_bot() }
  end

  def test_send_bot_one_arg
    assert_raises(ArgumentError) { send_bot("tyrannosaurus") }
  end

  def test_send_bot
    HTTParty.stub(:post, nil) do
      assert_nil send_bot("tyrannosaurus", [{"number" => "83.6"}, {"number" => "66.0"}])
    end
  end

  def test_interpolate_github_url_one_arg
    gem_name = "stegosaurus"
    assert_raises(ArgumentError) { interpolate_github_url(gem_name) }
  end

  def test_interpolate_github_url
    gem_name, newest, previous = "stegosaurus", "2.0", "1.0"
    assert_kind_of String, interpolate_github_url(gem_name, newest, previous)
  end

  def test_interpolate_rubygems_url_one_arg
    assert_raises(ArgumentError) { interpolate_rubygems_url() }
  end

  def test_interpolate_rubygems_url
    gem_name = "velociraptor"
    assert_kind_of String, interpolate_rubygems_url(gem_name)
  end

  def test_cve_bot_text_zero_args
    assert_raises(ArgumentError) { cve_bot_text() }
  end

  def test_cve_bot_text_one_arg
    assert_raises(ArgumentError) { cve_bot_text("allosaurus") }
  end

  def test_cve_bot_text
    text = cve_bot_text("allosaurus", "dinotracker.com")
    assert_equal text, '{"text":":rotating_light: allosaurus\n<dinotracker.com|More info here>"}'
    assert_kind_of String, text
  end

  def test_cve_send_bot_zero_args
    assert_raises(ArgumentError) { cve_send_bot() }
  end

  def test_cve_send_bot_one_arg
    assert_raises(ArgumentError) { cve_send_bot("brachiosaurus") }
  end

  def test_cve_send_bot
    HTTParty.stub(:post, nil) do
      assert_nil cve_send_bot("brachiosaurus", "dinotracker.com")
    end
  end
end
