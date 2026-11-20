# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Aws
      CHARACTERS = %w[A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 2 3 4 5 6 7].freeze
      HEX_MASK = '7fffffffff80'
      DEFAULT_PARTITION = 'aws'
      REGION_PREFIX_PARTITIONS = [
        ['cn-', 'aws-cn'],
        ['us-gov-', 'aws-us-gov'],
        ['us-isob-', 'aws-iso-b'],
        ['us-iso-', 'aws-iso'],
        ['eu-isoe-', 'aws-iso-e'],
        ['us-isof-', 'aws-iso-f'],
        ['eusc-', 'aws-eusc']
      ].freeze

      def self.create_arn(service, resource, region, account_id)
        # if any of the values are nil, we can't create an ARN
        return unless service && resource && region && account_id

        partition = partition_from_region(region.to_s)
        "arn:#{partition}:#{service}:#{region}:#{account_id}:#{resource}"
      rescue => e
        NewRelic::Agent.logger.warn("Failed to create ARN: #{e}")
      end

      def self.partition_from_region(region)
        sdk_partition_from_region(region) || table_partition_from_region(region)
      end

      def self.sdk_partition_from_region(region)
        return if region.empty? || !defined?(::Aws::Endpoints::Matchers) || !::Aws::Endpoints::Matchers.respond_to?(:aws_partition)

        ::Aws::Endpoints::Matchers.aws_partition(region)&.fetch('name', nil)
      rescue => e
        NewRelic::Agent.logger.debug("Failed to get AWS partition from SDK: #{e}")
        nil
      end

      def self.table_partition_from_region(region)
        REGION_PREFIX_PARTITIONS.each do |prefix, partition|
          return partition if region.start_with?(prefix)
        end
        DEFAULT_PARTITION
      end

      def self.get_account_id(config)
        # if it is set in the agent config, use that first
        return NewRelic::Agent.config[:'cloud.aws.account_id'] if NewRelic::Agent.config[:'cloud.aws.account_id']

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
