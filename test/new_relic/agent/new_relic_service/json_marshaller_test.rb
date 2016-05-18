# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'../../..','test_helper'))
require 'new_relic/agent/new_relic_service/json_marshaller'
require 'new_relic/agent/new_relic_service/encoders'

module NewRelic
  module Agent
    class NewRelicService
      class JsonMarshallerTest < Minitest::Test
        def test_default_encoder_is_base64_compressed_json
          marshaller = JsonMarshaller.new
          assert_equal Encoders::Base64CompressedJSON, marshaller.default_encoder
        end

        def test_default_encoder_is_identity_with_simple_compression_enabled
          marshaller = JsonMarshaller.new
          with_config :simple_compression => true do
            assert_equal Encoders::Identity, marshaller.default_encoder
          end
        end
      end
    end
  end
end
