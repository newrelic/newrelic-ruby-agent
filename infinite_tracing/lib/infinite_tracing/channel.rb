# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Channel

      def stub
        NewRelic::Agent.logger.debug "Infinite Tracer Opening Channel to #{host_and_port}"

        Com::Newrelic::Trace::V1::IngestService::Stub.new \
          host_and_port, 
          credentials, 
          channel_override: channel
      end

      def channel
        GRPC::Core::Channel.new(host_and_port, settings, credentials)
      end
      
      def credentials
        if Config.local?
          :this_channel_is_insecure 
        else
          # Uses system configured certificates by default
          GRPC::Core::ChannelCredentials.new
        end
      end

      def host_and_port
        Config.trace_observer_host_and_port
      end

      def settings
        {
          'grpc.minimal_stack' => 1,
          'grpc.enable_deadline_checking' => 0,
        }
      end

    end
  end
end
