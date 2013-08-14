# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/browser_token'

module NewRelic::Agent
  class BrowserTokenTest < Test::Unit::TestCase
    def assert_token(expected, cookies)
      request = stub(:cookies => cookies)
      assert_equal(expected, BrowserToken.get_token(request))
    end

    def test_get_token_safe_token_returned_untouched
      assert_token("12345678", 'NRAGENT' => 'tk=12345678')
    end

    def test_get_token_with_embedded_tags_sanitized
      assert_token("", 'NRAGENT' => 'tk=1234<tag>evil</tag>5678')
    end

    def test_get_token_with_embedded_utf8_js_sanitized
      assert_token("1234&amp;#34&amp;#93&amp;#41&amp;#595678", 'NRAGENT' => "tk=1234&#34&#93&#41&#595678")
    end

    def test_get_token_replaces_double_quoted_token_with_empty_string
      assert_token("", 'NRAGENT' => 'tk="""deadbeef"""')
    end

    def test_get_token_replaces_single_quoted_token_with_empty_string
      assert_token("", 'NRAGENT' => "tk='''deadbeef'''")
    end

    def test_get_token_replaces_token_started_with_multiple_Lt_with_empty_string
      assert_token("", 'NRAGENT' => 'tk=<<<deadbeef')
    end

    def test_get_token_replaces_token_started_with_multiple_gt_with_empty_string
      assert_token("", 'NRAGENT' => 'tk=>>>deadbeef')
    end

    def test_get_token_bare_value_replaced_with_nil
      assert_token(nil, 'NRAGENT' => 0xdeadbeef)
    end

    def test_get_token_nil_token_returns_nil_token
      assert_token(nil, 'NRAGENT' => nil)
    end

  end
end
