# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/http_clients/uri_util'

class URIUtilTest < Minitest::Test
  def test_obfuscated
    assert_obfuscated("http://foo.com/bar/baz",
      "http://foo.com/bar/baz")
  end

  def test_obfuscated_custom_port
    assert_obfuscated("http://foo.com:1234/bar/baz",
      "http://foo.com:1234/bar/baz")
  end

  def test_obfuscated_omits_query_params
    assert_obfuscated("http://foo.com/bar/baz?a=1&b=2",
      "http://foo.com/bar/baz")
  end

  def test_obfuscated_omits_fragment
    assert_obfuscated("http://foo.com/bar/baz#fragment",
      "http://foo.com/bar/baz")
  end

  def test_obfuscated_omits_query_params_and_fragment
    assert_obfuscated("http://foo.com/bar/baz?a=1&b=2#fragment",
      "http://foo.com/bar/baz")
  end

  def test_obfuscated_reflects_use_of_ssl
    assert_obfuscated("https://foo.com/bar/baz",
      "https://foo.com/bar/baz")
  end

  def test_obfuscated_reflects_use_of_ssl_with_custom_port
    assert_obfuscated("https://foo.com:9999/bar/baz",
      "https://foo.com:9999/bar/baz")
  end

  def test_obfuscated_with_full_uri_request_path
    assert_obfuscated("http://foo.com/bar/baz?a=1&b=2#fragment",
      "http://foo.com/bar/baz")
  end

  def test_obfuscated_with_full_uri_request_path_https
    assert_obfuscated("https://foo.com/bar/baz?a=1&b=2#fragment",
      "https://foo.com/bar/baz")
  end

  def test_strips_credentials_embedded_in_uri
    assert_obfuscated("http://user:pass@foo.com/bar/baz",
      "http://foo.com/bar/baz")
  end

  def test_invalid_url_normalization
    assert_normalized("foobarbaz",
      "foobarbaz")
  end

  def assert_obfuscated(original, expected)
    assert_equal expected, NewRelic::Agent::HTTPClients::URIUtil.obfuscated_uri(original).to_s
  end

  def assert_normalized(original, expected)
    assert_equal(expected, NewRelic::Agent::HTTPClients::URIUtil.parse_and_normalize_url(URI(original)).to_s)
  end

  def test_obfuscate_should_not_modify_uri_input
    test_urls = [
      ::URI.parse("https://foo.com/bar/baz?a=1&b=2#fragment"),
      "https://foo.com/bar/baz?a=1&b=2#fragment"
    ]

    test_urls.each do |original|
      to_obfuscate = original.dup
      NewRelic::Agent::HTTPClients::URIUtil.obfuscated_uri(to_obfuscate).to_s
      assert_equal original, to_obfuscate
    end
  end
end
