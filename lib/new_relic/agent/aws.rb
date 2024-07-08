# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Aws
      CHARACTERS = %w[A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 2 3 4 5 6 7].freeze
      HEX_MASK = '7fffffffff80'

      def self.create_arn(service, resource, region, account_id)
        "arn:aws:#{service}:#{region}:#{account_id}:#{resource}"
      rescue => e
        NewRelic::Agent.logger.warn("Failed to create ARN: #{e}")
      end

      def self.get_account_id(config)
        access_key_id = config.credentials.credentials.access_key_id if config&.credentials&.credentials&.respond_to?(:access_key_id)
        return unless access_key_id

        NewRelic::Agent::Aws.convert_access_key_to_account_id(access_key_id)
      rescue => e
        NewRelic::Agent.logger.debug("Failed to create account id: #{e}")
      end

      def self.convert_access_key_to_account_id(access_key)
        decoded_key = Integer(decode_to_hex(access_key[4..-1]), 16)
        mask = Integer(HEX_MASK, 16)
        (decoded_key & mask) >> 7
      end

      def self.decode_to_hex(access_key)
        bytes = access_key.delete('=').each_char.map { |c| CHARACTERS.index(c) }

        bytes.each_slice(8).map do |section|
          convert_section(section)
        end.flatten[0...6].join
      end

      def self.convert_section(section)
        buffer = 0
        section.each do |chunk|
          buffer = (buffer << 5) + chunk
        end

        chunk_count = (section.length * 5.0 / 8.0).floor

        if section.length < 8
          buffer >>= (5 - (chunk_count * 8)) % 5
        end

        decoded = []
        chunk_count.times do |i|
          shift = 8 * (chunk_count - 1 - i)
          decoded << ((buffer >> shift) & 255).to_s(16)
        end

        decoded
      end
    end
  end
end
