# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'base64'
require 'zlib'
require 'stringio'

module NewRelic
  module Agent
    class NewRelicService
      module Encoders
        module Identity
          def self.encode(data, opts=nil)
            data
          end
        end

        module Compressed
          module Deflate
            def self.encode(data, opts=nil)
              Zlib::Deflate.deflate(data, Zlib::DEFAULT_COMPRESSION)
            end
          end

          module Gzip
            BINARY = "BINARY".freeze

            def self.encode(data, opts=nil)
              output = StringIO.new
              output.set_encoding BINARY
              gz = Zlib::GzipWriter.new(output, Zlib::DEFAULT_COMPRESSION, Zlib::DEFAULT_STRATEGY)
              gz.write(data)
              output.rewind
              output.string
            end
          end
        end

        module Base64CompressedJSON
          def self.encode(data, opts={})
            normalize_encodings = if opts[:skip_normalization]
              false
            else
              Agent.config[:normalize_json_string_encodings]
            end
            json = ::NewRelic::JSONWrapper.dump(data, :normalize => normalize_encodings)
            Base64.encode64(Compressed::Deflate.encode(json))
          end
        end
      end
    end
  end
end
