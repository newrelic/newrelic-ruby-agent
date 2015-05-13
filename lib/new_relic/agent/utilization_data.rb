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
        @container_id ||= ::NewRelic::Agent::SystemInfo.docker_container_id
      end

      def cpu_count
        ::NewRelic::Agent::SystemInfo.clear_processor_info
        ::NewRelic::Agent::SystemInfo.num_logical_processors
      end

      def to_collector_hash
        result = {
          :metadata_version => METADATA_VERSION,
          :logical_processors => cpu_count,
          :hostname => hostname
        }

        vendors = {}
        vendors[:aws] = @aws_info.to_collector_hash if @aws_info.loaded?
        vendors[:docker] = {:id => container_id} if container_id
        result[:vendors] = vendors unless vendors.empty?
        result
      end
    end
  end
end
