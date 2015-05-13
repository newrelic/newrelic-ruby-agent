# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/aws_info'

module NewRelic
  module Agent
    class UtilizationData
      def initialize
        @aws_info = AWSInfo.new
      end

      def harvest!
        [hostname, container_id, cpu_count, instance_type]
      end

      # No persistent data, so no need for merging or resetting
      def merge!(*_); end
      def reset!(*_); end

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

      def instance_type
        @aws_info.instance_type
      end

      def instance_id
        @aws_info.instance_id
      end

      def availability_zone
        @aws_info.availability_zone
      end
    end
  end
end
