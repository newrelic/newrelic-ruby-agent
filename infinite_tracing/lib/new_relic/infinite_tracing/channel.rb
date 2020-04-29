# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Channel
      include Singleton

      def channel
        GRPC::ClientStub.setup_channel(nil, host_and_port, credentials, settings)
      end

      private
      
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

      # FOREVER = (2**(4 * 8 -2) -1)
      # THIRTY_SECONDS = 30_000
 
      # TODO: decide what defaults we want to use

      def settings
        {
          'grpc.minimal_stack' => 1,
          # 'grpc.arg_max_connection_idle_ms' => FOREVER,
          # 'grpc.keepalive_time_ms' => THIRTY_SECONDS,
          # 'grpc.keepalive_timeout_ms' => THIRTY_SECONDS,
          # 'grpc.keepalive_permit_without_calls' => THIRTY_SECONDS,
          # 'grpc.arg_max_concurrent_streams' => 10,
          # 'grpc.max_concurrent_streams' => 10,
          # 'grpc.max_connection_age_ms' => FOREVER,
          # 'grpc.enable_deadline_checking' => 0,
          # 'grpc.http2.max_pings_without_data' => 0,
          # 'grpc.http2.min_time_between_pings_ms' => 10000,
          # 'grpc.http2.min_ping_interval_without_data_ms' => 5000,
        }
      end

    end
  end
end
