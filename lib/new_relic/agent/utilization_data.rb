# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/aws_info'

module NewRelic
  module Agent
    class UtilizationData
      METADATA_VERSION = 1

      def initialize
        @aws_info = AWSInfo.new
      end

      def hostname
        NewRelic::Agent::Hostname.get
      end

      def container_id
        ::NewRelic::Agent::SystemInfo.docker_container_id
      end

      def cpu_count
        ::NewRelic::Agent::SystemInfo.clear_processor_info
        ::NewRelic::Agent::SystemInfo.num_logical_processors
      end

      def ram_in_mb
        ::NewRelic::Agent::SystemInfo.ram_in_mb
      end

      def to_collector_hash
        result = {
          :metadata_version => METADATA_VERSION,
          :logical_processors => cpu_count,
          :total_ram_mb => ram_in_mb,
          :hostname => hostname
        }

        vendors = {}
        vendors[:aws] = @aws_info.to_collector_hash if @aws_info.loaded?

        if docker_container_id = container_id
          vendors[:docker] = {:id => docker_container_id}
        end

        result[:vendors] = vendors unless vendors.empty?
        result
      end
    end
  end
end
