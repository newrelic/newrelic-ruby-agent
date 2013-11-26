# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require "new_relic/agent/obfuscator"

class NewRelic::Agent::ObfuscatorTest < Test::Unit::TestCase

  OBFUSCATION_KEY = (1..40).to_a.pack('c*')
  RUM_KEY_LENGTH  = 13

  def setup
    @config = { :license_key => OBFUSCATION_KEY }
    NewRelic::Agent.config.apply_config(@config)
  end

  def teardown
    NewRelic::Agent.config.remove_config(@config)
    @obfuscator = nil
  end

  def obfuscator(length=nil)
    @obfuscator ||= NewRelic::Agent::Obfuscator.new(OBFUSCATION_KEY, length)
  end

  def test_obfuscate_basic
    assert_encoded(RUM_KEY_LENGTH,
                   'a happy piece of small text',
                   'YCJrZXV2fih5Y25vaCFtZSR2a2ZkZSp/aXV1')
  end

  def test_obfuscate_long_string
    assert_encoded(RUM_KEY_LENGTH,
                   'a happy piece of small text' * 5,
                   'YCJrZXV2fih5Y25vaCFtZSR2a2ZkZSp/aXV1YyNsZHZ3cSl6YmluZCJsYiV1amllZit4aHl2YiRtZ3d4cCp7ZWhiZyNrYyZ0ZWhmZyx5ZHp3ZSVuZnh5cyt8ZGRhZiRqYCd7ZGtnYC11Z3twZCZvaXl6cix9aGdgYSVpYSh6Z2pgYSF2Znxx')
  end

  def test_obfuscate_utf8
    assert_encoded(RUM_KEY_LENGTH,
                   "foooooééoooo - blah",
                   "Z21sa2ppxKHKo2RjYm4iLiRnamZg")
  end

  def assert_encoded(key_length, text, expected)
    output = obfuscator(key_length).obfuscate(text)
    assert_equal(expected, output)

    unoutput = obfuscator.obfuscate(Base64.decode64(output))
    assert_equal Base64.encode64(text).gsub("\n", ''), unoutput
  end
end
