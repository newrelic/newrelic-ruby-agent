# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

#require 'base64'

module NewRelic
  module Agent
    class Obfuscator

      attr_reader :key

      # RUM uses a shortened key, so just trim it up front
      def initialize(key, length=nil)
        key = key[0...length] unless length.nil?
        key = key.bytes.to_a if key.respond_to?( :bytes )
        @key = key
      end

      def obfuscate(text)
        [ encode(text) ].pack('m').chomp.gsub(/\n/, '')
      end

      def decode(text)
        encode(text.unpack('m').first )
      end

      def encode(text)
        return text unless key

        encoded = ""
        encoded.force_encoding('binary') if encoded.respond_to?( :force_encoding )
        index = 0
        text.each_byte do |byte|
          encoded.concat((byte ^ key[index % key.length].to_i))
          index+=1
        end
        encoded
      end

    end
  end
end
