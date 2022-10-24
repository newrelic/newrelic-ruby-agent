# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    class Channel
      COMPRESSION_LEVELS = %w[none low medium high].freeze
      DEFAULT_COMPRESSION_LEVEL = 'none'

      def stub
        NewRelic::Agent.logger.debug("Infinite Tracer Opening Channel to #{host_and_port}")

        Com::Newrelic::Trace::V1::IngestService::Stub.new( \
          host_and_port,
          credentials,
          channel_override: channel,
          channel_args: channel_args
        )
      end

      def channel
        GRPC::Core::Channel.new(host_and_port, settings, credentials)
      end

      def channel_args
        return NewRelic::EMPTY_HASH unless compression_enabled?

        GRPC::Core::CompressionOptions.new(compression_options).to_channel_arg_hash
      end

      def compression_enabled?
        compression_level != DEFAULT_COMPRESSION_LEVEL
      end

      def compression_level
        @compression_level ||= begin
          level = if valid_compression_level?(configured_compression_level)
            configured_compression_level
          else
            DEFAULT_COMPRESSION_LEVEL
          end
          NewRelic::Agent.logger.debug("Infinite Tracer compression level set to #{level}")
          level
        end
      end

      def compression_options
        {default_algorithm: :gzip,
         default_level: compression_level}
      end

      def configured_compression_level
        NewRelic::Agent.config[:'infinite_tracing.compression_level']
      end

      def credentials
        # Uses system configured certificates by default
        GRPC::Core::ChannelCredentials.new
      end

      def host_and_port
        Config.trace_observer_host_and_port
      end

      def settings
        {
          'grpc.minimal_stack' => 1,
          'grpc.enable_deadline_checking' => 0
        }
      end

      def valid_compression_level?(level)
        return true if COMPRESSION_LEVELS.include?(level)

        NewRelic::Agent.logger.error("Invalid compression level '#{level}' specified! Must be one of " \
          "#{COMPRESSION_LEVELS.join('|')}. Using default level of '#{DEFAULT_COMPRESSION_LEVEL}'")

        false
      end
    end
  end
end
