# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

#require 'base64'

module NewRelic
  module Agent
    class Obfuscator

      attr_reader :license_bytes

      def initialize(key, length=nil)
        # RUM uses a shortened key, so just trim it up front
        key = key[0...length] unless length.nil?

        @license_bytes = []
        key.each_byte {|byte| @license_bytes << byte}
      end

      # Obfuscation

      def obfuscate(text)
        obfuscated = ""
        if defined?(::Encoding::ASCII_8BIT)
          obfuscated.force_encoding(::Encoding::ASCII_8BIT)
        end

        index = 0
        text.each_byte{|byte|
          obfuscated.concat((byte ^ license_bytes[index % license_bytes.length].to_i))
          index+=1
        }

        [obfuscated].pack("m0").gsub("\n", '')
      end

    end
  end
end
