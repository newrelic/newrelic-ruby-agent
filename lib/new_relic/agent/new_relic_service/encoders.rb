# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'
require 'zlib'

module NewRelic
  module Agent
    class NewRelicService
      module Encoders
        module Identity
          def self.encode(data)
            data
          end
        end

        module Compressed
          def self.encode(data)
            Zlib::Deflate.deflate(data, Zlib::DEFAULT_COMPRESSION)
          end
        end

        module Base64CompressedJSON
          def self.encode(data)
            json = ::NewRelic::JSONWrapper.dump(data,
              :normalize => Agent.config[:normalize_json_string_encodings])
            Base64.encode64(Compressed.encode(json))
          end
        end
      end
    end
  end
end
