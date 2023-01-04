# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Channel
      SETTINGS_BASE = {'grpc.enable_deadline_checking' => 0}.freeze
      SETTINGS_COMPRESSION_DISABLED = SETTINGS_BASE.merge({'grpc.minimal_stack' => 1}).freeze

      def stub
        NewRelic::Agent.logger.debug("Infinite Tracer Opening Channel to #{host_and_port}")

        Com::Newrelic::Trace::V1::IngestService::Stub.new( \
          host_and_port,
          credentials,
          channel_override: channel,
          channel_args: channel_args
        )
      end

      def host_and_port
        Config.trace_observer_host_and_port
      end

      def credentials
        @credentials ||= GRPC::Core::ChannelCredentials.new
      end

      def channel
        GRPC::Core::Channel.new(host_and_port, settings, credentials)
      end

      def settings
        return channel_args.merge(SETTINGS_COMPRESSION_DISABLED).freeze unless Config.compression_enabled?

        channel_args.merge(SETTINGS_BASE).freeze
      end

      def channel_args
        return NewRelic::EMPTY_HASH unless Config.compression_enabled?

        GRPC::Core::CompressionOptions.new(default_algorithm: :gzip,
          default_level: Config.compression_level).to_channel_arg_hash
      end
    end
  end
end
