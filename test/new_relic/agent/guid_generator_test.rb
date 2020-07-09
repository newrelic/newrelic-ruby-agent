# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/guid_generator'

module NewRelic
  module Agent
    class GuidGeneratorTest < Minitest::Test

      def test_generate_guid
        guid = NewRelic::Agent::GuidGenerator.generate_guid
        # the result should be exactly 16 hexadecimal characters
        assert_match(/[a-f0-9]{16}/, guid)
      end

      def test_generate_guid_custom_length
        guid = NewRelic::Agent::GuidGenerator.generate_guid 32
        # the result should be exactly 32 hexadecimal characters
        assert_match(/[a-f0-9]{32}/, guid)
      end
    end
  end
end
