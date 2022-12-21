# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
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
        guid = NewRelic::Agent::GuidGenerator.generate_guid(32)
        # the result should be exactly 32 hexadecimal characters
        assert_match(/[a-f0-9]{32}/, guid)
      end

      def test_max_rand_16_constant
        canned = 1234567890123456
        NewRelic::Agent::GuidGenerator.stub_const(:MAX_RAND_16, canned..canned) do
          guid = NewRelic::Agent::GuidGenerator.generate_guid(16)

          assert_equal '000462d53c8abac0', guid
        end
      end

      def test_max_rand_32_constant
        canned = 12345678901234567890123456789012
        NewRelic::Agent::GuidGenerator.stub_const(:MAX_RAND_32, canned..canned) do
          guid = NewRelic::Agent::GuidGenerator.generate_guid(32)

          assert_equal '0000009bd30a3c645943dd1690a03a14', guid
        end
      end

      def test_non_rjust
        canned = NewRelic::Agent::GuidGenerator::MAX_RAND_32
        NewRelic::Agent::GuidGenerator.stub_const(:MAX_RAND_32, canned..canned) do
          guid = NewRelic::Agent::GuidGenerator.generate_guid(32)

          assert_equal '100000000000000000000000000000000', guid
        end
      end

      def test_rjust
        canned = 1138
        NewRelic::Agent::GuidGenerator.stub_const(:MAX_RAND_16, canned..canned) do
          guid = NewRelic::Agent::GuidGenerator.generate_guid(16)

          assert_equal '0000000000000472', guid
        end
      end
    end
  end
end
